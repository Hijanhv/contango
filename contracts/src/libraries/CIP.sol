// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {WadMath} from "./WadMath.sol";

/// @title CIP — Covered Interest Parity
/// @notice The pricing kernel of the protocol. An FX forward is not an opinion
///         about the future: it is spot plus the cost of carrying the two
///         currencies to the value date. No-arbitrage pins it exactly:
///
///             F = S · (1 + r_USD·τ) / (1 + r_EUR·τ)
///
///         with S the USDC/EURC spot mid (USD per EUR), r_USD the SOFR fixing,
///         r_EUR the €STR fixing, and τ the ACT/360 year fraction to the value
///         date. When r_USD > r_EUR the curve is upward-sloping — *contango* —
///         and the difference F − S is the forward points the desk earns for
///         carrying the position.
library CIP {
    using WadMath for uint256;

    uint256 internal constant WAD = 1e18;
    /// @dev FX money-market convention: ACT/360, matching how SOFR and €STR are quoted.
    uint256 internal constant DAY_COUNT_BASIS = 360 days;

    /// @notice ACT/360 year fraction between two timestamps, in WAD.
    function yearFraction(uint256 from, uint256 to) internal pure returns (uint256) {
        if (to <= from) return 0;
        return ((to - from) * WAD) / DAY_COUNT_BASIS;
    }

    /// @notice Covered-interest-parity forward rate, in WAD (USD per EUR).
    /// @param spot   USDC/EURC spot mid, WAD.
    /// @param rUsd   USD money-market rate (SOFR), annualised, WAD (0.0530e18 = 5.30%).
    /// @param rEur   EUR money-market rate (€STR), annualised, WAD.
    /// @param tau    ACT/360 year fraction to the value date, WAD.
    function forward(uint256 spot, uint256 rUsd, uint256 rEur, uint256 tau) internal pure returns (uint256) {
        if (tau == 0) return spot;
        uint256 numerator = WAD + rUsd.mulWad(tau);
        uint256 denominator = WAD + rEur.mulWad(tau);
        return (spot * numerator) / denominator;
    }

    /// @notice Forward points: F − S, signed, in WAD. Positive ⇒ contango.
    function forwardPoints(uint256 spot, uint256 rUsd, uint256 rEur, uint256 tau) internal pure returns (int256) {
        return int256(forward(spot, rUsd, rEur, tau)) - int256(spot);
    }

    /// @notice Invert a traded forward back into the rate differential it implies.
    ///         This is what makes the book a *curve*: every quoted tenor is a
    ///         market-clearing USD−EUR rate differential, which is the primitive
    ///         other Arc protocols can consume.
    /// @return diff Annualised (r_USD − r_EUR) implied by `fwd`, signed WAD.
    function impliedRateDifferential(uint256 spot, uint256 fwd, uint256 tau) internal pure returns (int256 diff) {
        if (tau == 0 || spot == 0) return 0;
        int256 ratio = int256((fwd * WAD) / spot) - int256(WAD);
        return (ratio * int256(WAD)) / int256(tau);
    }
}
