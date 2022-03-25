// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;

import {ITokenPriceManagerMinimal} from "./ITokenPriceManagerMinimal.sol";

/// @title Address database for TokenPriceManagers
/// @author Peter T. Flynn
/// @notice Allows for access to TokenPriceManagers by their primary token's symbol, with
/// easy upgradeability in mind.
interface ITokenPriceControllerDefault {
    /// @notice Gets the address of a TokenPriceManager, given the primary token's symbol
    /// @param symbol The primary token's symbol, formatted identically to its contract variable
    function getManager(string calldata symbol)
        external
        view
        returns 
        (ITokenPriceManagerMinimal);
}
