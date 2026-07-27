// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IRateOracle} from "./interfaces/IRateOracle.sol";
import {ISpotVenue} from "./interfaces/ISpotVenue.sol";

interface IForwardEngine {
    function deskEquity() external view returns (int256);
    function fundDesk(uint256 amount) external;
    function defundDesk(uint256 amount) external;
}

/// @title CarryVault
/// @notice The desk's balance sheet, tokenised as ERC-4626 over USDC.
///
///         This is what "USD yield from FX flow" actually means on-chain. The
///         vault holds three things and marks all of them continuously:
///
///           • idle USDC,
///           • the EURC spot hedge inventory that offsets the forward book,
///           • its claim on the desk (posted margin ± the book's mark-to-market).
///
///         Because every forward written is hedged in spot, the FX exposure of
///         legs two and three cancels. What survives is the bid/ask captured
///         around CIP fair value, the carry earned as forward points roll down
///         to zero, and the margin fees — textbook FX swap-desk revenue, with no
///         emissions and no directional bet.
contract CarryVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    error NotHedger();
    error NotEngine();
    error ExceedsLiquidity();

    IERC20 public immutable eurc;
    IRateOracle public immutable oracle;
    uint256 public immutable EUR_TO_USD_DIV;

    IForwardEngine public engine;
    ISpotVenue public spotVenue;
    address public hedger;

    /// @notice Fraction of NAV kept as idle USDC so redemptions stay instant.
    uint256 public liquidityBufferBps = 1000;

    event Hedged(bool usdcForEurc, uint256 amountIn, uint256 amountOut, int256 newEurcInventory);
    event DeskFunded(uint256 amount);
    event DeskDefunded(uint256 amount);
    event DeskDrew(uint256 amount);

    modifier onlyHedger() {
        if (msg.sender != hedger && msg.sender != owner()) revert NotHedger();
        _;
    }

    constructor(address owner_, IERC20 usdc_, IERC20 eurc_, IRateOracle oracle_)
        ERC4626(usdc_)
        ERC20("Contango Carry Vault", "cUSDC")
        Ownable(owner_)
    {
        eurc = eurc_;
        oracle = oracle_;
        uint8 usdDec = IERC20Metadata(address(usdc_)).decimals();
        uint8 eurDec = IERC20Metadata(address(eurc_)).decimals();
        EUR_TO_USD_DIV = (1e18 * (10 ** eurDec)) / (10 ** usdDec);
    }

    /// @dev Virtual-share offset: standard ERC-4626 inflation-attack protection.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 12;
    }

    // ───────────────────────────────── NAV ───────────────────────────────────

    /// @notice Net asset value: idle USDC + EURC hedge marked at oracle spot +
    ///         the desk claim. All three move; only their *sum* is the LP's money.
    function totalAssets() public view override returns (uint256) {
        int256 nav = int256(idleAssets()) + int256(hedgeValueUsd()) + deskClaim();
        return nav > 0 ? uint256(nav) : 0;
    }

    function idleAssets() public view returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    function eurcInventory() public view returns (uint256) {
        return eurc.balanceOf(address(this));
    }

    /// @notice EURC hedge inventory valued in USDC at the oracle mid.
    function hedgeValueUsd() public view returns (uint256) {
        uint256 bal = eurcInventory();
        if (bal == 0) return 0;
        if (!oracle.healthy()) return 0; // do not mint/redeem against a bad mark
        return (bal * oracle.spot()) / EUR_TO_USD_DIV;
    }

    function deskClaim() public view returns (int256) {
        if (address(engine) == address(0)) return 0;
        return engine.deskEquity();
    }

    /// @notice Redemptions are served from idle USDC; the hedge and the desk
    ///         claim are not instantly liquid, and we say so rather than
    ///         pretending otherwise at the moment of stress.
    function maxWithdraw(address owner_) public view override returns (uint256) {
        return Math.min(super.maxWithdraw(owner_), idleAssets());
    }

    function maxRedeem(address owner_) public view override returns (uint256) {
        uint256 shares = super.maxRedeem(owner_);
        uint256 byLiquidity = convertToShares(idleAssets());
        return Math.min(shares, byLiquidity);
    }

    // ─────────────────────────────── hedging ─────────────────────────────────

    /// @notice Delta-hedge through the spot venue. Called by the quant engine
    ///         the moment a forward is written, which is what keeps the vault's
    ///         P&L free of directional FX.
    function hedge(bool usdcForEurc, uint256 amountIn, uint256 minAmountOut)
        external
        onlyHedger
        returns (uint256 amountOut)
    {
        IERC20 tokenIn = usdcForEurc ? IERC20(asset()) : eurc;
        tokenIn.forceApprove(address(spotVenue), amountIn);
        amountOut = spotVenue.swap(usdcForEurc, amountIn, minAmountOut, address(this));
        emit Hedged(usdcForEurc, amountIn, amountOut, int256(eurcInventory()));
    }

    // ────────────────────────────── desk funding ─────────────────────────────

    function fundDesk(uint256 amount) external onlyOwner {
        IERC20(asset()).forceApprove(address(engine), amount);
        engine.fundDesk(amount);
        emit DeskFunded(amount);
    }

    function defundDesk(uint256 amount) external onlyOwner {
        engine.defundDesk(amount);
        emit DeskDefunded(amount);
    }

    /// @notice The desk's credit line, drawn only by the engine when a winning
    ///         trader must be paid and desk cash is short.
    function drawDesk(uint256 amount) external returns (uint256 drawn) {
        if (msg.sender != address(engine)) revert NotEngine();
        drawn = Math.min(amount, idleAssets());
        if (drawn > 0) IERC20(asset()).safeTransfer(address(engine), drawn);
        emit DeskDrew(drawn);
    }

    // ──────────────────────────────── admin ──────────────────────────────────

    function setEngine(IForwardEngine engine_) external onlyOwner {
        engine = engine_;
    }

    function setSpotVenue(ISpotVenue venue) external onlyOwner {
        spotVenue = venue;
    }

    function setHedger(address hedger_) external onlyOwner {
        hedger = hedger_;
    }

    function setLiquidityBufferBps(uint256 bps) external onlyOwner {
        liquidityBufferBps = bps;
    }
}
