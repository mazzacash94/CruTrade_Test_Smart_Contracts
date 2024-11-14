// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './errors/Errors.sol';
import './interfaces/IRoles.sol';
import './abstracts/RolesVariables.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts/access/IAccessControl.sol';

/**
 * @title Roles
 * @notice Manages roles within the Crutrade ecosystem.
 */
contract Roles is
  Initializable,
  UUPSUpgradeable,
  PausableUpgradeable,
  IRoles,
  RolesVariables,
  AccessControlUpgradeable
{
  /* INITIALIZATION */

  /**
   * @dev Disables initializers for this contract.
   */
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev Initializes the contract with the default admin role.
   * @param defaultAdmin Address of the default admin.
   */
  function initialize(address defaultAdmin) public initializer {
    __Pausable_init();
    __AccessControl_init();
    __UUPSUpgradeable_init();

    _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    _addresses[DEFAULT_ADMIN_ROLE] = defaultAdmin;
  }

  /* VARIABLES */

  /* MAPPINGS */

  mapping(address => bool) private _payments;
  mapping(address => bool) private _delegated;
  mapping(bytes32 => address) private _addresses;

  /* GETTERS */

  /**
   * @dev Returns the address associated with a specific role.
   * @param role Role to query.
   * @return Address associated with the role.
   */
  function getRoleAddress(
    bytes32 role
  ) external view override returns (address) {
    return _addresses[role];
  }

  /**
   * @dev Checks if a contract has the payment role.
   * @param _contract Address of the contract to check.
   * @return `true` if the contract has the payment role.
   */
  function hasPaymentRole(
    address _contract
  ) external view override returns (bool) {
    return _payments[_contract];
  }

  /**
   * @dev Checks if a contract has been delegated.
   * @param _contract Address of the contract to check.
   * @return `true` if the contract has been delegated.
   */
  function hasDelegateRole(
    address _contract
  ) public view virtual override returns (bool) {
    return _delegated[_contract];
  }

  /* SETTERS */

  /**
   * @dev Pauses the contract.
   * Can only be called by an account with the PAUSER role.
   */
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /**
   * @dev Unpauses the contract.
   * Can only be called by an account with the PAUSER role.
   */
  function unpause() external onlyRole(PAUSER) {
    _unpause();
  }

  /**
   * @dev Grants the payment role to a specific address.
   * @param payment Address to grant the payment role.
   */
  function grantPaymentRole(
    address payment
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _payments[payment] = true;
    emit PaymentRoleGranted(payment);
  }

  /**
   * @dev Revokes the payment role from a specific address.
   * @param payment Address to revoke the payment role.
   */
  function revokePaymentRole(
    address payment
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _payments[payment] = false;
    emit PaymentRoleRevoked(payment);
  }

  /**
   * @dev Grants the delegate role to a specific address.
   * @param _contract Address to grant the delegate role.
   */
  function grantDelegateRole(
    address _contract
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _delegated[_contract] = true;
    emit DelegateRoleGranted(_contract);
  }

  /**
   * @dev Revokes the delegate role from a specific address.
   * @param _contract Address to revoke the delegate role.
   */
  function revokeDelegateRole(
    address _contract
  ) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _delegated[_contract] = false;
    emit DelegateRoleRevoked(_contract);
  }

  /* OVERRIDES */

  function grantRole(
    bytes32 role,
    address account
  )
    public
    virtual
    override(AccessControlUpgradeable, IAccessControl)
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _addresses[role] = account;
    _grantRole(role, account);
  }

  /**
   * @dev Authorizes the upgrade of the contract.
   * @param newImplementation Address of the new implementation contract.
   */
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(UPGRADER) {}
}
