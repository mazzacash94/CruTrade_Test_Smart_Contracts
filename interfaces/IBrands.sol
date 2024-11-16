// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Structs
struct Brand {
    address token;
    string rules;
    address owner;
}

// Events
event RulesUpdated(uint indexed brandId, string rules);
event Registered(address token, string rules, uint96 indexed brandId);

// Errors
error BrandNotFound(uint256 brandId);
error InvalidBrandToken(address token);
error InvalidBrandOwner(address owner);

interface IBrands {
    function isValidBrand(uint256 brandId) external view returns (bool);
    function getBrand(uint256 brandId) external view returns (Brand memory);
    function getBrandToken(uint256 brandId) external view returns (address);
}