// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './errors/Errors.sol';
import './interfaces/IRoles.sol';
import './interfaces/IWhitelist.sol';
import { IAccessControl } from '@openzeppelin/contracts/access/IAccessControl.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { UUPSUpgradeable } from '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import { Modifiers } from './abstracts/Modifiers.sol';

// EVENTS

/*
     __       __  __    __  ______  ________  ________  __        ______   ______   ________ 
    |  \  _  |  \|  \  |  \|      \|        \|        \|  \      |      \ /      \ |        \
    | $$ / \ | $$| $$  | $$ \$$$$$$ \$$$$$$$$| $$$$$$$$| $$       \$$$$$$|  $$$$$$\ \$$$$$$$$
    | $$/  $\| $$| $$__| $$  | $$     | $$   | $$__    | $$        | $$  | $$___\$$   | $$   
    | $$  $$$\ $$| $$    $$  | $$     | $$   | $$  \   | $$        | $$   \$$    \    | $$   
    | $$ $$\$$\$$| $$$$$$$$  | $$     | $$   | $$$$$   | $$        | $$   _\$$$$$$\   | $$   
    | $$$$  \$$$$| $$  | $$ _| $$_    | $$   | $$_____ | $$_____  _| $$_ |  \__| $$   | $$   
    | $$$    \$$$| $$  | $$|   $$ \   | $$   | $$     \| $$     \|   $$ \ \$$    $$   | $$   
     \$$      \$$ \$$   \$$ \$$$$$$    \$$    \$$$$$$$$ \$$$$$$$$ \$$$$$$  \$$$$$$     \$$   
                                                                                                                                        
*/

/// @title Whitelist
/// @author mazzaca$h (https://www.linkedin.com/in/mazzacash/)
/// @notice Manages users in the whitelist within the Crutrade ecosystem.
contract Whitelist is
  Initializable,
  UUPSUpgradeable,
  IWhitelist,
  PausableUpgradeable,
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
   * @dev Initializes the contract with roles.
   * @param roles Address of the roles contract.
   */
  function initialize(address roles) public initializer {
    __Pausable_init();
    __UUPSUpgradeable_init();
    __Modifiers_init(roles);
  }

  /* MAPPINGS */

  mapping(address => bool) private _whitelisted;

  /* SETTERS */

  /**
   * @dev Updates the roles contract address.
   * @param _roles Address of the new roles contract.
   */
  function setRoles(address _roles) external payable onlyRole(OWNER) {
    roles = IRoles(_roles);
    emit RolesSet(_roles);
  }

  /**
   * @dev Pauses the contract.
   * Can only be called by an account with the PAUSER role.
   */
  function pause() external payable onlyRole(PAUSER) {
    _pause();
  }

  /**
   * @dev Unpauses the contract.
   * Can only be called by an account with the PAUSER role.
   */
  function unpause() external payable onlyRole(PAUSER) {
    _unpause();
  }

  /**
   * @dev Adds a wallet to the whitelist.
   * @param wallets Address to add to the whitelist.
   * Requirements:
   * - Contract must not be paused.
   * - Caller must have the WHITELISTER role.
   *
   * Emits a {Add} event.
   */
  function addToWhitelist(
    address[] calldata wallets
  ) external whenNotPaused onlyRole(WHITELISTER) {
    uint length = wallets.length;
    for (uint i; i < length; i++) {
      address wallet = wallets[i];
      _whitelisted[wallet] = true;
    }
    emit Add(wallets);
  }

  /**
   * @dev Removes a wallet from the whitelist.
   * @param wallets Address to remove from the whitelist.
   * Requirements:
   * - Contract must not be paused.
   * - Caller must have the WHITELISTER role.
   *
   * Emits a {Remove} event.
   */
  function removeFromWhitelist(
    address[] calldata wallets
  ) external whenNotPaused onlyRole(WHITELISTER) {
    uint length = wallets.length;
    for (uint i; i < length; i++) {
      address wallet = wallets[i];
      _whitelisted[wallet] = false;
    }
    emit Remove(wallets);
  }

  /* OVERRIDES */

  /**
   * @dev Checks if a wallet is in the whitelist.
   * @param wallet Address to check.
   * @return `true` if the wallet is whitelisted.
   */
  function isWhitelisted(address wallet) external view override returns (bool) {
    return _whitelisted[wallet];
  }

  /**
   * @dev Authorizes the upgrade of the contract.
   * @param newImplementation Address of the new implementation contract.
   */
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(UPGRADER) {}
}
