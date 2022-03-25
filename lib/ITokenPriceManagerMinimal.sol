// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;

/// @title Price maintainer for arbitrary tokens
/// @author Peter T. Flynn
/// @notice Maintains a common interface for requesting the price of the given token, with
/// special functionality for TokenSets.
/// @dev Contract must be initialized before use. Price should always be requested using 
/// getPrice(PriceType), rather than viewing the [price] variable. Price returned is dependent
/// on the transactor's SWD balance. Constants require adjustment for deployment outside Polygon. 
interface ITokenPriceManagerMinimal {
    // @notice Affects the application of the "spread fee" when requesting token price
    enum PriceType { BUY, SELL, RAW }
    
    /// @notice Gets the current price of the primary token, denominated in [tokenDenominator]
    /// @dev Returns a different value, depending on the SWD balance of tx.origin's wallet.
    /// If the balance is over the threshold, getPrice() will return the price unmodified,
    /// otherwise it adds the dictated fee. Tx.origin is purposefully used over msg.sender,
    /// so as to be compatible with DEx aggregators. As a side effect, this makes it incompatible
    /// with relays. Price is always returned with 18 decimals of precision, regardless of token
    /// decimals. Manual adjustment of precision must be done later for [tokenDenominator]s
    /// with less precision.
    /// @param priceType "BUY" for buying, "SELL" for selling,
    /// and "RAW" for a direct price request
    /// @return uint256 Current price in [tokenDenominator], per primary token
    /// @return address Current [tokenDenominator], may be address(0) to indicate USD
    function getPrice(PriceType priceType) external view returns (uint256, address);

    /// @return address Current [tokenPrimary]
    function getTokenPrimary() external view returns (address);

    /// @return address Current [tokenDenominator], may be address(0) to indicate USD
    function getTokenDenominator() external view returns (address);
}