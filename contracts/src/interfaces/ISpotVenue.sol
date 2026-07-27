// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ISpotVenue
/// @notice The desk's hedge execution surface. Every forward Contango writes is
///         immediately delta-hedged in spot through this interface, which is why
///         the vault earns spread + carry and never directional FX.
///
///         Today the implementation is Circle's App Kit Swap (USDC↔EURC with a
///         configurable spread fee). `StableFXVenue` snaps in behind the same
///         interface the moment Circle issues an RFQ key — no protocol change.
interface ISpotVenue {
    /// @param usdcForEurc true = sell USDC buy EURC; false = sell EURC buy USDC.
    function quote(bool usdcForEurc, uint256 amountIn) external view returns (uint256 amountOut);

    function swap(bool usdcForEurc, uint256 amountIn, uint256 minAmountOut, address recipient)
        external
        returns (uint256 amountOut);

    function venueName() external view returns (string memory);
}
