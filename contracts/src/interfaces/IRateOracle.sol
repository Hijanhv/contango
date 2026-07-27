// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRateOracle {
    /// @notice Medianised USDC/EURC spot mid, WAD (USD per EUR). Reverts if unhealthy.
    function spot() external view returns (uint256);

    /// @notice Latest published money-market fixings, annualised WAD.
    function fixings() external view returns (uint256 rUsd, uint256 rEur);

    /// @notice CIP forward rate for a listed expiry, WAD.
    function forwardRate(uint256 expiry) external view returns (uint256);

    /// @notice Fixing recorded at expiry; 0 until `recordSettlement` runs.
    function settlementPrice(uint256 expiry) external view returns (uint256);

    /// @notice False when stale, when sources disagree, or when the breaker is tripped.
    function healthy() external view returns (bool);
}
