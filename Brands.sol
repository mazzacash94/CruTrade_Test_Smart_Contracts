// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './abstracts/Modifiers.sol';
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @dev Emitted when the rules of a brand are updated.
 * @param brandId ID of the brand.
 * @param rules New rules for the brand.
 */
event RulesUpdated(uint indexed brandId, string rules);

/**
 * @dev Emitted when a brand is registered.
 * @param token Address of the token.
 * @param rules Rules of the brand.
 * @param brandId ID of the registered brand.
 */
event Registered(address token, string rules, uint96 indexed brandId);

/**
 * @title Brands
 * @notice Manages brands within the Crutrade ecosystem.
 */
contract Brands is
    Initializable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IBrands,
    Modifiers
{
    /* INITIALIZATION */

    /**
     * @dev Disables initializers for this contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the roles contract address.
     * @param _roles Address of the roles contract.
     */
    function initialize(address _roles) public initializer {
        __Pausable_init();
        __UUPSUpgradeable_init();
        __Modifiers_init(_roles);
    }

    /* VARIABLES */

    uint88 private _brandIdCounter;

    /* MAPPINGS */

    mapping(uint256 => Brand) private _brands;

    /* PUBLIC FUNCTIONS */

    /**
     * @dev Retrieves the brand information for a given brand ID.
     * @param brandId ID of the brand.
     * @return Brand struct containing token address and rules.
     */
    function getBrand(uint256 brandId) public view override returns (Brand memory) {
        return _brands[brandId];
    }

    /**
     * @dev Pauses the contract.
     * Can only be called by an account with the OWNER role.
     */
    function pause() external onlyRole(OWNER) {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     * Can only be called by an account with the OWNER role.
     */
    function unpause() external onlyRole(OWNER) {
        _unpause();
    }

    /**
     * @dev Updates the roles contract address.
     * @param _roles Address of the new roles contract.
     */
    function setRoles(address _roles) external onlyRole(OWNER) {
        roles = IRoles(_roles);
        emit RolesSet(_roles);
    }

    /**
     * @dev Registers a new brand.
     * @param token Address of the brand's token.
     * @param rules Rules of the brand.
     */
    function register(address token, address owner, string calldata rules) external onlyRole(OWNER) {
        _brands[_brandIdCounter] = Brand(token, rules, owner);
        emit Registered(token, rules, _brandIdCounter);
        unchecked {
            _brandIdCounter++;
        }
    }

    /**
     * @dev Updates the rules for an existing brand.
     * @param brandId ID of the brand to update.
     * @param rules New rules for the brand.
     */
    function updateRules(uint brandId, string calldata rules) external onlyRole(OWNER) {
        _brands[brandId].rules = rules;
        emit RulesUpdated(brandId, rules);
    }

    /* OVERRIDES */

    /**
     * @dev Checks if a brand is valid based on its ID.
     * @param brandId ID of the brand.
     * @return True if the brand is valid, otherwise false.
     */
    function isValidBrand(uint256 brandId) external view override returns (bool) {
        return _brands[brandId].token != address(0);
    }

    /**
     * @dev Retrieves the token address for a given brand ID.
     * @param brandId ID of the brand.
     * @return Address of the brand's token.
     */
    function getBrandToken(uint256 brandId) external view override returns (address) {
        return _brands[brandId].token;
    }

    /**
     * @dev Authorizes the upgrade of the contract.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER) {}
}
