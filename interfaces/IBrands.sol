// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
/**
 * @dev Represents a brand with a token and associated rules.
 * @param token Address of the brand's token.
 * @param rules String representing the rules of the brand.
 */
struct Brand {
  address token;
  string rules;
  address owner;
}

interface IBrands {
  function isValidBrand(uint256 brandId) external view returns (bool);

  function getBrand(uint256 brandId) external view returns (Brand memory);

  function getBrandToken(uint256 brandId) external view returns (address);
}
