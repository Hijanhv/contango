// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISpotVenue} from "../interfaces/ISpotVenue.sol";
import {IRateOracle} from "../interfaces/IRateOracle.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Local stand-in for App Kit Swap: fills at the oracle mid minus a
///         configurable spread fee, which is exactly the execution-cost model
///         the quant engine budgets for when it sizes a hedge.
contract MockSpotVenue is ISpotVenue {
    using SafeERC20 for IERC20;

    MockERC20 public immutable usdc;
    MockERC20 public immutable eurc;
    IRateOracle public immutable oracle;
    uint256 public immutable EUR_TO_USD_DIV;
    uint256 public spreadFeeBps;

    constructor(MockERC20 usdc_, MockERC20 eurc_, IRateOracle oracle_, uint256 spreadFeeBps_) {
        usdc = usdc_;
        eurc = eurc_;
        oracle = oracle_;
        spreadFeeBps = spreadFeeBps_;
        EUR_TO_USD_DIV = (1e18 * (10 ** eurc_.decimals())) / (10 ** usdc_.decimals());
    }

    function venueName() external pure returns (string memory) {
        return "MockSpotVenue";
    }

    function quote(bool usdcForEurc, uint256 amountIn) public view returns (uint256 amountOut) {
        uint256 s = oracle.spot();
        amountOut = usdcForEurc ? (amountIn * EUR_TO_USD_DIV) / s : (amountIn * s) / EUR_TO_USD_DIV;
        amountOut = (amountOut * (10_000 - spreadFeeBps)) / 10_000;
    }

    function swap(bool usdcForEurc, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut)
    {
        amountOut = quote(usdcForEurc, amountIn);
        require(amountOut >= minAmountOut, "MockSpotVenue: slippage");
        if (usdcForEurc) {
            IERC20(address(usdc)).safeTransferFrom(msg.sender, address(this), amountIn);
            eurc.mint(recipient, amountOut);
        } else {
            IERC20(address(eurc)).safeTransferFrom(msg.sender, address(this), amountIn);
            usdc.mint(recipient, amountOut);
        }
    }

    function setSpreadFeeBps(uint256 bps) external {
        spreadFeeBps = bps;
    }
}
