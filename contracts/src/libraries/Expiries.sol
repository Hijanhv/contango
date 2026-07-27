// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Expiries
/// @notice Contango trades a listed curve, not arbitrary dates: value dates are
///         fixed weekly at Friday 16:00 UTC (the WM/Reuters fixing hour London
///         desks settle against). Listing discrete tenors concentrates liquidity
///         into a handful of points and makes the whole book markable from a
///         single oracle read per expiry.
library Expiries {
    uint256 internal constant WEEK = 7 days;
    /// @dev 1 Jan 1970 was a Thursday, so Friday 16:00 UTC ≡ t % 1 week == 144000.
    uint256 internal constant FRIDAY_1600_UTC = 1 days + 16 hours;

    /// @notice True if `timestamp` lands on a listed weekly expiry.
    function isListed(uint256 timestamp) internal pure returns (bool) {
        return timestamp % WEEK == FRIDAY_1600_UTC;
    }

    /// @notice The first listed expiry strictly after `timestamp`.
    function firstAfter(uint256 timestamp) internal pure returns (uint256) {
        uint256 weekStart = timestamp - (timestamp % WEEK);
        uint256 candidate = weekStart + FRIDAY_1600_UTC;
        if (candidate <= timestamp) candidate += WEEK;
        return candidate;
    }

    /// @notice The `n`-th listed expiry after `timestamp` (n = 1 ⇒ front week).
    function nth(uint256 timestamp, uint256 n) internal pure returns (uint256) {
        require(n > 0, "Expiries: n=0");
        return firstAfter(timestamp) + (n - 1) * WEEK;
    }
}
