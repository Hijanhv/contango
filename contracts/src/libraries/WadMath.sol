// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title WadMath
/// @notice Minimal fixed-point helpers. `WAD` = 1e18 and is the unit for every
///         *price* and *rate* in Contango. Token amounts keep their own decimals
///         (USDC/EURC = 6 on Circle's canonical deployments).
library WadMath {
    uint256 internal constant WAD = 1e18;
    int256 internal constant WAD_INT = 1e18;

    error MathOverflow();

    function mulWad(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * b) / WAD;
    }

    function divWad(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a * WAD) / b;
    }

    function mulWadInt(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / WAD_INT;
    }

    function abs(int256 a) internal pure returns (uint256) {
        return a >= 0 ? uint256(a) : uint256(-a);
    }

    function toInt(uint256 a) internal pure returns (int256) {
        if (a > uint256(type(int256).max)) revert MathOverflow();
        return int256(a);
    }

    /// @notice Absolute deviation of `a` from `b`, in basis points of `b`.
    function deviationBps(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) return type(uint256).max;
        uint256 diff = a > b ? a - b : b - a;
        return (diff * 10_000) / b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
