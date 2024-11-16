// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Structs
struct Data {
    bytes32 sku;
    uint256 wrapperId;
}

struct WrapperInput {
    string uri;
    bytes32 sku;
    uint256[] ids;
}

struct Wrapper {
    string uri;
    bytes32 sku;
    uint256[] ids;
    uint256 brandId;
}

// Events
event BatchTransfer(
    address indexed from,
    address to,
    uint256[] tokenIds
);

event Import(Data[] data, address to);
event Export(address indexed wallet, uint[] ids);
event MarketplaceTransfer(
    address indexed from,
    address indexed to,
    uint256 indexed wrapperId
);

// Errors
error InvalidWrapper(uint256 wrapperId);
error InvalidCollection(uint256 brandId, bytes32 category);
error UnauthorizedTransfer(address from, address to);

interface IWrappers {
    function isValidCollection(uint brandId, bytes32 category) external view returns (bool);
    function getData(uint256 tokenId) external view returns (Wrapper memory);
    function marketplaceTransfer(address from, address to, uint tokenId) external;
    function getBrand(uint256 tokenId) external view returns (uint256);
    function checkCollection(bytes32 category, uint256 wrapperId) external view returns (bool);
}