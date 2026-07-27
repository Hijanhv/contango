// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IRateOracle} from "./interfaces/IRateOracle.sol";
import {CIP} from "./libraries/CIP.sol";
import {Expiries} from "./libraries/Expiries.sol";
import {WadMath} from "./libraries/WadMath.sol";

interface ICarryVault {
    function idleAssets() external view returns (uint256);
    function drawDesk(uint256 amount) external returns (uint256);
}

/// @title ForwardEngine
/// @notice A margined, cash-settled EURUSD forward book — the instrument TradFi
///         can only sell you through an ISDA and a bank credit line.
///
///         The substitution is the whole thesis: a forward is a promise that has
///         to survive until expiry, and TradFi wraps that promise in *credit*.
///         Here it is wrapped in *margin* — initial margin sized to the 99th
///         percentile weekly EURUSD move, continuous mark-to-market against a
///         medianised oracle, and keeper liquidation that is final in one block
///         because Arc's consensus is deterministic and non-reorgable. That is
///         what collapses the minimum ticket from $1,000,000 to $1, and what
///         lets the book stay open on a Saturday.
///
///         The protocol desk is the counterparty to every ticket; `CarryVault`
///         is its balance sheet. Marking the desk's book to CIP fair value makes
///         the P&L decomposition fall out for free: entering at the quoted side
///         books the spread on day one, and the roll-down of forward points as
///         τ → 0 *is* the carry. Directional FX is neutralised by the spot hedge
///         the vault holds, so vault P&L = spread + carry + margin fees.
contract ForwardEngine is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using WadMath for uint256;
    using WadMath for int256;

    // ──────────────────────────────── types ──────────────────────────────────

    struct Position {
        address trader;
        uint64 expiry;
        bool isLong; // long = buy EUR forward
        bool closed;
        uint128 notionalEur; // EURC base units
        uint128 entryPrice; // WAD, USD per EUR — the rate actually locked
        uint128 margin; // USDC base units
        uint128 notionalUsdOpen; // USDC base units at entry, for exact book unwind
        uint64 openedAt;
    }

    struct PositionView {
        int256 pnl;
        int256 equity;
        uint256 initialMargin;
        uint256 maintenanceMargin;
        uint256 markPrice;
        bool liquidatable;
    }

    struct CurvePoint {
        uint256 expiry;
        uint256 fair;
        uint256 bid;
        uint256 ask;
        int256 forwardPoints;
        int256 impliedRateDiff;
        int256 netNotionalEur;
    }

    error NotListedExpiry();
    error TenorTooShort();
    error TicketTooSmall();
    error InsufficientMargin();
    error SlippageExceeded();
    error OracleUnhealthy();
    error NotOpen();
    error NotTrader();
    error NotLiquidatable();
    error NotExpired();
    error NoSettlementFixing();
    error DeskAtCapacity();
    error SkewTooLarge();
    error ZeroNotional();
    error Paused();

    // ─────────────────────────────── immutables ──────────────────────────────

    IERC20 public immutable usdc;
    IERC20 public immutable eurc;
    IRateOracle public immutable oracle;
    /// @dev WAD scaled for the decimal gap between the two legs, so
    ///      usd = eur * price / EUR_TO_USD_DIV holds for any pair of decimals.
    uint256 public immutable EUR_TO_USD_DIV;

    // ──────────────────────────────── config ─────────────────────────────────

    ICarryVault public vault;

    /// @notice IM 8% — sized to the 99th-percentile weekly EURUSD move (~1.5%)
    ///         with a wide multiple, because the desk cannot make a margin call
    ///         by phone at 3am on a Sunday.
    uint256 public imBps = 800;
    uint256 public mmBps = 400;
    uint256 public openFeeBps = 5; // margin/booking fee on notional → desk
    uint256 public halfSpreadBps = 8; // quoted each side of skewed mid
    uint256 public liqPenaltyBps = 100;
    uint256 public keeperShareBps = 5000; // half the penalty to whoever liquidates
    uint256 public minTicketUsd; // set in constructor to $1
    uint256 public minTenor = 1 days;
    uint256 public maxNetNotionalEur; // inventory scale for the skew function
    uint256 public deskCoverBps = 1000; // desk must hold 10% of open interest
    /// @notice Avellaneda–Stoikov-lite risk aversion: how hard the quoted mid is
    ///         pushed away from fair value per unit of inventory imbalance.
    uint256 public inventoryKWad = 0.002e18;
    int256 public manualSkewWad; // quant engine's alpha overlay, bounded
    int256 public maxManualSkewWad = 0.002e18;
    bool public paused;

    address public quoter; // off-chain quant engine

    // ──────────────────────────────── state ──────────────────────────────────

    uint256 public nextPositionId = 1;
    mapping(uint256 => Position) public positions;

    /// @dev Aggregates let the desk mark its whole book with one oracle read per
    ///      listed expiry instead of iterating positions.
    mapping(uint256 => int256) public netNotionalEur; // trader side, signed
    mapping(uint256 => int256) public netEntryValueUsd; // Σ notional·entry
    uint256[] public activeExpiries;
    mapping(uint256 => bool) public isActiveExpiry;

    uint256 public totalTraderMargin;
    uint256 public deskCash;
    uint256 public deskCapital; // cumulative net USDC provided by the vault
    int256 public deskRealizedPnl;
    uint256 public openInterestUsd;
    uint256 public totalBadDebt;

    event PositionOpened(
        uint256 indexed id,
        address indexed trader,
        uint256 indexed expiry,
        bool isLong,
        uint256 notionalEur,
        uint256 entryPrice,
        uint256 fairPrice,
        uint256 margin,
        uint256 fee
    );
    event PositionClosed(uint256 indexed id, address indexed trader, uint256 exitPrice, int256 pnl, uint256 payout);
    event PositionLiquidated(
        uint256 indexed id, address indexed keeper, uint256 markPrice, int256 pnl, uint256 penalty, uint256 payout
    );
    event PositionSettled(uint256 indexed id, uint256 settlementPrice, int256 pnl, uint256 payout);
    event MarginAdjusted(uint256 indexed id, int256 delta, uint256 newMargin);
    event SkewUpdated(int256 manualSkewWad);
    event DeskFunded(uint256 amount, uint256 deskCash);
    event DeskDefunded(uint256 amount, uint256 deskCash);
    event BadDebt(uint256 indexed id, uint256 amount);

    modifier whenLive() {
        if (paused) revert Paused();
        if (!oracle.healthy()) revert OracleUnhealthy();
        _;
    }

    constructor(address owner_, IERC20 usdc_, IERC20 eurc_, IRateOracle oracle_) Ownable(owner_) {
        usdc = usdc_;
        eurc = eurc_;
        oracle = oracle_;
        uint8 usdDec = IERC20Metadata(address(usdc_)).decimals();
        uint8 eurDec = IERC20Metadata(address(eurc_)).decimals();
        EUR_TO_USD_DIV = (1e18 * (10 ** eurDec)) / (10 ** usdDec);
        minTicketUsd = 10 ** usdDec; // $1 minimum ticket. Not a typo.
        maxNetNotionalEur = 1_000_000 * (10 ** eurDec);
    }

    // ─────────────────────────────── quoting ─────────────────────────────────

    /// @notice Inventory-skewed quote around CIP fair value.
    ///         mid = F · (1 + skew), skew = −k · (deskInventory / maxInventory)
    ///         so the desk's own axe moves the price: when the book is one-sided
    ///         the next ticket on that side pays up, and the opposite side is
    ///         paid to flatten it. Bounded manual skew lets the off-chain engine
    ///         express its own alpha on top without ever escaping these rails.
    function quote(uint256 expiry, bool isLong) public view returns (uint256 price, uint256 fair) {
        fair = oracle.forwardRate(expiry);
        int256 skew = skewWad();
        uint256 mid = uint256(int256(fair) + (int256(fair) * skew) / 1e18);
        price = isLong ? (mid * (10_000 + halfSpreadBps)) / 10_000 : (mid * (10_000 - halfSpreadBps)) / 10_000;
    }

    /// @notice Signed skew applied to fair value, WAD.
    function skewWad() public view returns (int256) {
        int256 deskInventory = -_totalNetNotionalEur(); // desk is the other side
        int256 ratio = (deskInventory * 1e18) / int256(maxNetNotionalEur);
        if (ratio > 1e18) ratio = 1e18;
        if (ratio < -1e18) ratio = -1e18;
        int256 skew = -(int256(inventoryKWad) * ratio) / 1e18;
        return skew + manualSkewWad;
    }

    /// @notice The forward curve, ready for the dashboard: `n` listed weekly tenors.
    function curve(uint256 n) external view returns (CurvePoint[] memory points) {
        points = new CurvePoint[](n);
        uint256 s = oracle.spot();
        for (uint256 i; i < n; ++i) {
            uint256 expiry = Expiries.nth(block.timestamp, i + 1);
            (uint256 ask, uint256 fair) = quote(expiry, true);
            (uint256 bid,) = quote(expiry, false);
            uint256 tau = CIP.yearFraction(block.timestamp, expiry);
            points[i] = CurvePoint({
                expiry: expiry,
                fair: fair,
                bid: bid,
                ask: ask,
                forwardPoints: int256(fair) - int256(s),
                impliedRateDiff: CIP.impliedRateDifferential(s, fair, tau),
                netNotionalEur: netNotionalEur[expiry]
            });
        }
    }

    // ──────────────────────────────── trading ────────────────────────────────

    /// @notice Lock a EURUSD rate for a listed value date.
    /// @param isLong      true = buy EUR forward (the importer with a EUR invoice).
    /// @param notionalEur Notional in EURC base units.
    /// @param expiry      A listed weekly expiry (Friday 16:00 UTC).
    /// @param limitPrice  Worst acceptable rate — long caps, short floors.
    /// @param margin      USDC posted; must cover initial margin plus the fee.
    function open(bool isLong, uint256 notionalEur, uint256 expiry, uint256 limitPrice, uint256 margin)
        external
        nonReentrant
        whenLive
        returns (uint256 id)
    {
        if (notionalEur == 0) revert ZeroNotional();
        if (!Expiries.isListed(expiry)) revert NotListedExpiry();
        if (expiry < block.timestamp + minTenor) revert TenorTooShort();

        (uint256 price, uint256 fair) = quote(expiry, isLong);
        if (isLong ? price > limitPrice : price < limitPrice) revert SlippageExceeded();

        uint256 notionalUsd = _eurToUsd(notionalEur, price);
        if (notionalUsd < minTicketUsd) revert TicketTooSmall();

        uint256 fee = (notionalUsd * openFeeBps) / 10_000;
        if (margin < (notionalUsd * imBps) / 10_000 + fee) revert InsufficientMargin();

        usdc.safeTransferFrom(msg.sender, address(this), margin);
        deskCash += fee;
        totalTraderMargin += margin - fee;
        deskRealizedPnl += int256(fee);

        id = nextPositionId++;
        positions[id] = Position({
            trader: msg.sender,
            expiry: uint64(expiry),
            isLong: isLong,
            closed: false,
            notionalEur: uint128(notionalEur),
            entryPrice: uint128(price),
            margin: uint128(margin - fee),
            notionalUsdOpen: uint128(notionalUsd),
            openedAt: uint64(block.timestamp)
        });

        _bookOpen(expiry, isLong ? int256(notionalEur) : -int256(notionalEur), price, notionalUsd);
        _requireDeskCapacity();

        emit PositionOpened(id, msg.sender, expiry, isLong, notionalEur, price, fair, margin - fee, fee);
    }

    function _bookOpen(uint256 expiry, int256 signedEur, uint256 price, uint256 notionalUsd) internal {
        _touchExpiry(expiry);
        netNotionalEur[expiry] += signedEur;
        netEntryValueUsd[expiry] += _eurToUsdInt(signedEur, price);
        openInterestUsd += notionalUsd;
    }

    /// @notice Close early at the current quote (crossing the spread again).
    function close(uint256 id) external nonReentrant whenLive {
        Position storage p = positions[id];
        if (p.closed) revert NotOpen();
        if (p.trader != msg.sender) revert NotTrader();

        (uint256 exitPrice,) = quote(p.expiry, !p.isLong); // unwinding hits the other side
        int256 pnl = _pnl(p, exitPrice);
        uint256 payout = _closeOut(id, p, pnl, 0, address(0));
        emit PositionClosed(id, p.trader, exitPrice, pnl, payout);
    }

    function addMargin(uint256 id, uint256 amount) external nonReentrant {
        Position storage p = positions[id];
        if (p.closed) revert NotOpen();
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        p.margin += uint128(amount);
        totalTraderMargin += amount;
        emit MarginAdjusted(id, int256(amount), p.margin);
    }

    /// @notice Withdraw excess margin, never below initial margin at the mark.
    function removeMargin(uint256 id, uint256 amount) external nonReentrant whenLive {
        Position storage p = positions[id];
        if (p.closed) revert NotOpen();
        if (p.trader != msg.sender) revert NotTrader();

        uint256 mark = markPrice(p.expiry);
        int256 equity = int256(uint256(p.margin)) + _pnl(p, mark);
        uint256 im = (_eurToUsd(p.notionalEur, mark) * imBps) / 10_000;
        if (equity < int256(im + amount)) revert InsufficientMargin();

        p.margin -= uint128(amount);
        totalTraderMargin -= amount;
        usdc.safeTransfer(msg.sender, amount);
        emit MarginAdjusted(id, -int256(amount), p.margin);
    }

    /// @notice Close an under-margined position. Permissionless: on Arc the
    ///         liquidation is final in the block it lands in, so the keeper race
    ///         is a race to a settled outcome, not to a reorg.
    function liquidate(uint256 id) external nonReentrant whenLive {
        Position storage p = positions[id];
        if (p.closed) revert NotOpen();

        uint256 mark = markPrice(p.expiry);
        int256 pnl = _pnl(p, mark);
        int256 equity = int256(uint256(p.margin)) + pnl;
        uint256 mm = (_eurToUsd(p.notionalEur, mark) * mmBps) / 10_000;
        if (equity >= int256(mm)) revert NotLiquidatable();

        uint256 penalty = (_eurToUsd(p.notionalEur, mark) * liqPenaltyBps) / 10_000;
        if (equity > 0 && uint256(equity) < penalty) penalty = uint256(equity);
        if (equity <= 0) penalty = 0;

        uint256 payout = _closeOut(id, p, pnl, penalty, msg.sender);
        emit PositionLiquidated(id, msg.sender, mark, pnl, penalty, payout);
    }

    /// @notice Cash-settle an expired ticket against the recorded fixing.
    function settle(uint256 id) external nonReentrant {
        Position storage p = positions[id];
        if (p.closed) revert NotOpen();
        if (block.timestamp < p.expiry) revert NotExpired();
        uint256 fix = oracle.settlementPrice(p.expiry);
        if (fix == 0) revert NoSettlementFixing();

        int256 pnl = _pnl(p, fix);
        uint256 payout = _closeOut(id, p, pnl, 0, address(0));
        emit PositionSettled(id, fix, pnl, payout);
    }

    // ───────────────────────────── desk plumbing ─────────────────────────────

    /// @notice Vault posts desk capital.
    function fundDesk(uint256 amount) external nonReentrant {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        deskCash += amount;
        deskCapital += amount;
        emit DeskFunded(amount, deskCash);
    }

    /// @notice Vault reclaims idle desk capital, subject to the cover ratio.
    function defundDesk(uint256 amount) external nonReentrant {
        if (msg.sender != address(vault) && msg.sender != owner()) revert NotTrader();
        deskCash -= amount;
        if (deskCapital >= amount) deskCapital -= amount;
        else deskCapital = 0;
        _requireDeskCapacity();
        usdc.safeTransfer(msg.sender, amount);
        emit DeskDefunded(amount, deskCash);
    }

    // ───────────────────────────────── views ─────────────────────────────────

    /// @notice Mark for an expiry: CIP forward while live, the fixing once set.
    function markPrice(uint256 expiry) public view returns (uint256) {
        uint256 fix = oracle.settlementPrice(expiry);
        if (fix != 0) return fix;
        return oracle.forwardRate(expiry);
    }

    function positionState(uint256 id) external view returns (PositionView memory v) {
        Position memory p = positions[id];
        v.markPrice = markPrice(p.expiry);
        v.pnl = _pnl(p, v.markPrice);
        v.equity = int256(uint256(p.margin)) + v.pnl;
        uint256 notionalUsd = _eurToUsd(p.notionalEur, v.markPrice);
        v.initialMargin = (notionalUsd * imBps) / 10_000;
        v.maintenanceMargin = (notionalUsd * mmBps) / 10_000;
        v.liquidatable = !p.closed && v.equity < int256(v.maintenanceMargin);
    }

    /// @notice Desk mark-to-market. Because the desk is the exact opposite of the
    ///         aggregate trader book, one read per listed expiry marks everything.
    function deskUnrealizedPnl() public view returns (int256 pnl) {
        uint256 n = activeExpiries.length;
        for (uint256 i; i < n; ++i) {
            uint256 e = activeExpiries[i];
            int256 net = netNotionalEur[e];
            if (net == 0 && netEntryValueUsd[e] == 0) continue;
            int256 traderPnl = _eurToUsdInt(net, markPrice(e)) - netEntryValueUsd[e];
            pnl -= traderPnl;
        }
    }

    /// @notice What the vault's share of the desk is worth right now.
    function deskEquity() external view returns (int256) {
        return int256(deskCash) + deskUnrealizedPnl();
    }

    function activeExpiryCount() external view returns (uint256) {
        return activeExpiries.length;
    }

    function listedExpiry(uint256 n) external view returns (uint256) {
        return Expiries.nth(block.timestamp, n);
    }

    /// @dev Solvency accounting identity, asserted by the invariant suite:
    ///      every USDC in the engine is either trader margin or desk cash.
    function cashInvariantHolds() external view returns (bool) {
        return usdc.balanceOf(address(this)) == totalTraderMargin + deskCash;
    }

    // ──────────────────────────────── internal ───────────────────────────────

    function _pnl(Position memory p, uint256 mark) internal view returns (int256) {
        int256 signedEur = p.isLong ? int256(uint256(p.notionalEur)) : -int256(uint256(p.notionalEur));
        return (signedEur * (int256(mark) - int256(uint256(p.entryPrice)))) / int256(EUR_TO_USD_DIV);
    }

    function _closeOut(uint256 id, Position storage p, int256 pnl, uint256 penalty, address keeper)
        internal
        returns (uint256 payout)
    {
        uint256 margin = p.margin;
        totalTraderMargin -= margin;

        // Unwind the book aggregates exactly as they were added.
        int256 signedEur = p.isLong ? int256(uint256(p.notionalEur)) : -int256(uint256(p.notionalEur));
        netNotionalEur[p.expiry] -= signedEur;
        netEntryValueUsd[p.expiry] -= _eurToUsdInt(signedEur, p.entryPrice);
        openInterestUsd = openInterestUsd > p.notionalUsdOpen ? openInterestUsd - p.notionalUsdOpen : 0;

        p.closed = true;

        int256 equity = int256(margin) + pnl;
        if (equity <= 0) {
            // Trader is past their margin: the desk takes the collateral and eats
            // the remainder as bad debt. Surfaced, never hidden.
            deskCash += margin;
            deskRealizedPnl += int256(margin);
            uint256 shortfall = uint256(-equity);
            if (shortfall > 0) {
                totalBadDebt += shortfall;
                emit BadDebt(id, shortfall);
            }
            return 0;
        }

        if (pnl >= 0) {
            uint256 owed = uint256(pnl);
            _ensureDeskCash(owed);
            deskCash -= owed;
            deskRealizedPnl -= int256(owed);
        } else {
            uint256 gain = uint256(-pnl);
            deskCash += gain;
            deskRealizedPnl += int256(gain);
        }

        payout = uint256(equity);
        if (penalty > 0) {
            payout -= penalty;
            uint256 keeperCut = (penalty * keeperShareBps) / 10_000;
            deskCash += penalty;
            deskRealizedPnl += int256(penalty);
            if (keeperCut > 0 && keeper != address(0)) {
                deskCash -= keeperCut;
                deskRealizedPnl -= int256(keeperCut);
                usdc.safeTransfer(keeper, keeperCut);
            }
        }
        if (payout > 0) usdc.safeTransfer(p.trader, payout);
    }

    /// @dev The desk's credit line: draw idle vault assets before failing a payout.
    function _ensureDeskCash(uint256 needed) internal {
        if (deskCash >= needed) return;
        uint256 short = needed - deskCash;
        if (address(vault) != address(0)) {
            uint256 drawn = vault.drawDesk(short);
            deskCash += drawn;
            deskCapital += drawn;
        }
        if (deskCash < needed) revert DeskAtCapacity();
    }

    function _requireDeskCapacity() internal view {
        uint256 required = (openInterestUsd * deskCoverBps) / 10_000;
        uint256 available = deskCash;
        if (address(vault) != address(0)) available += vault.idleAssets();
        if (available < required) revert DeskAtCapacity();
    }

    function _touchExpiry(uint256 expiry) internal {
        if (!isActiveExpiry[expiry]) {
            isActiveExpiry[expiry] = true;
            activeExpiries.push(expiry);
        }
    }

    function _totalNetNotionalEur() internal view returns (int256 total) {
        uint256 n = activeExpiries.length;
        for (uint256 i; i < n; ++i) {
            total += netNotionalEur[activeExpiries[i]];
        }
    }

    function _eurToUsd(uint256 eurAmount, uint256 price) internal view returns (uint256) {
        return (eurAmount * price) / EUR_TO_USD_DIV;
    }

    function _eurToUsdInt(int256 eurAmount, uint256 price) internal view returns (int256) {
        return (eurAmount * int256(price)) / int256(EUR_TO_USD_DIV);
    }

    // ──────────────────────────────── admin ──────────────────────────────────

    function setVault(ICarryVault vault_) external onlyOwner {
        vault = vault_;
    }

    function setQuoter(address quoter_) external onlyOwner {
        quoter = quoter_;
    }

    /// @notice The quant engine's alpha overlay on top of the on-chain skew.
    function setManualSkew(int256 skew) external {
        if (msg.sender != quoter && msg.sender != owner()) revert NotTrader();
        if (skew > maxManualSkewWad || skew < -maxManualSkewWad) revert SkewTooLarge();
        manualSkewWad = skew;
        emit SkewUpdated(skew);
    }

    function setRiskParams(uint256 imBps_, uint256 mmBps_, uint256 halfSpreadBps_, uint256 openFeeBps_)
        external
        onlyOwner
    {
        require(mmBps_ < imBps_ && imBps_ <= 5000, "bad margin tiers");
        imBps = imBps_;
        mmBps = mmBps_;
        halfSpreadBps = halfSpreadBps_;
        openFeeBps = openFeeBps_;
    }

    function setDeskParams(uint256 maxNetNotionalEur_, uint256 deskCoverBps_, uint256 inventoryKWad_) external onlyOwner {
        maxNetNotionalEur = maxNetNotionalEur_;
        deskCoverBps = deskCoverBps_;
        inventoryKWad = inventoryKWad_;
    }

    function setPaused(bool paused_) external onlyOwner {
        paused = paused_;
    }
}
