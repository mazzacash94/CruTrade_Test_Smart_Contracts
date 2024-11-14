// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Wrapper Management Contract
/// @notice This contract manages the import, export, and transfer of wrapper tokens
/// @dev Implements functionality for handling wrapper tokens and collections

//------------------------------------------------------------------------------
// Events
//------------------------------------------------------------------------------

/// @dev Event emitted when tokens are batch transferred
event BatchTransfer(
    address indexed from,
    address to,
    uint256[] tokenIds
);

/// @notice Emitted when data is imported to a specific address
/// @param data Array of Data structs containing imported information
/// @param to Address receiving the imported data
event Import(Data[] data, address to);

/// @notice Emitted when tokens are exported from a wallet
/// @param wallet Address from which tokens are exported
/// @param ids Array of token IDs being exported
event Export(address indexed wallet, uint[] ids);

/// @notice Emitted when a wrapper token is transferred in the marketplace
/// @param from Address sending the token
/// @param to Address receiving the token
/// @param wrapperId ID of the wrapper token being transferred
event MarketplaceTransfer(
    address indexed from,
    address indexed to,
    uint256 indexed wrapperId
);

//------------------------------------------------------------------------------
// Structs
//------------------------------------------------------------------------------

/*
  struct Collection {
    mapping(uint265 => Wrapper) wrappers;
    EnumerableSet.UintSet wrapperIds;
  }
*/

/// @notice Struct representing imported data
/// @param sku Unique identifier for the product
/// @param wrapperId ID of the wrapper token
struct Data {
    bytes32 sku;
    uint wrapperId;
}

/// @notice Struct for input when creating a wrapper
/// @param uri URI for the wrapper metadata
/// @param sku Unique identifier for the product
/// @param ids Array of token IDs to be included in the wrapper
struct WrapperInput {
    string uri;
    bytes32 sku;
    uint256[] ids;
}

/// @notice Struct representing a wrapper token
/// @param uri URI for the wrapper metadata
/// @param sku Unique identifier for the product
/// @param ids Array of token IDs included in the wrapper
/// @param brandId ID of the brand associated with the wrapper
struct Wrapper {
    string uri;
    bytes32 sku;
    uint256[] ids;
    uint256 brandId;
}

//------------------------------------------------------------------------------
// Interfaces
//------------------------------------------------------------------------------

/// @title Interface for Wrappers contract
/// @notice Defines functions for interacting with wrapper tokens
interface IWrappers {
    /// @notice Checks if a collection is valid for a given brand and category
    /// @param brandId ID of the brand
    /// @param category Category of the collection
    /// @return bool Indicating if the collection is valid
    function isValidCollection(
        uint brandId,
        bytes32 category
    ) external view returns (bool);

    /// @notice Retrieves data for a given wrapper token
    /// @param tokenId ID of the wrapper token
    /// @return Wrapper struct containing the token data
    function getData(uint256 tokenId) external view returns (Wrapper memory);

    /// @notice Transfers a wrapper token between addresses without requiring approval
    /// @param from Address sending the token
    /// @param to Address receiving the token
    /// @param tokenId ID of the wrapper token to transfer
    function marketplaceTransfer(
        address from,
        address to,
        uint tokenId
    ) external payable;

    /// @notice Gets the brand ID associated with a wrapper token
    /// @param tokenId ID of the wrapper token
    /// @return uint256 Brand ID of the token
    function getBrand(uint256 tokenId) external view returns (uint256);

    /// @notice Checks if a wrapper belongs to a specific collection
    /// @param category Category of the collection
    /// @param wrapperId ID of the wrapper token
    /// @return bool Indicating if the wrapper belongs to the collection
    function checkCollection(
        bytes32 category,
        uint256 wrapperId
    ) external view returns (bool);
}