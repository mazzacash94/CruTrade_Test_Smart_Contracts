// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title RolesVariables
 * @dev Defines constant role identifiers for the Crutrade ecosystem.
 * These constants are used across various contracts to manage permissions and access control.
 */
abstract contract RolesVariables {
  /** @dev Team-related role identifiers */
  bytes32 internal constant FIAT = keccak256('FIAT');
  bytes32 internal constant SWAP = keccak256('SWAP');
  bytes32 internal constant SERVICE = keccak256('SERVICE');
  bytes32 internal constant TREASURY = keccak256('TREASURY');

  /** @dev Relayer role identifiers for various operational permissions */
  bytes32 internal constant DROPS = keccak256('DROPS');
  bytes32 internal constant OWNER = keccak256('OWNER');
  bytes32 internal constant BUYER = keccak256('BUYER');
  bytes32 internal constant PAUSER = keccak256('PAUSER');
  bytes32 internal constant LISTER = keccak256('LISTER');
  bytes32 internal constant RENEWER = keccak256('RENEWER');
  bytes32 internal constant PRESALER = keccak256('PRESALER');
  bytes32 internal constant IMPORTER = keccak256('IMPORTER');
  bytes32 internal constant EXPORTER = keccak256('EXPORTER');
  bytes32 internal constant UPGRADER = keccak256('UPGRADER');
  bytes32 internal constant WITHDRAWER = keccak256('WITHDRAWER');
  bytes32 internal constant WHITELISTER = keccak256('WHITELISTER');
  bytes32 internal constant MEMBERSHIPPER = keccak256('MEMBERSHIPPER');
  bytes32 internal constant STAKER = keccak256('STAKER');

  /** @dev Operation-related identifiers */
  bytes32 internal constant BUY = keccak256('BUY');
  bytes32 internal constant LIST = keccak256('LIST');
  bytes32 internal constant RENEW = keccak256('RENEW');
  bytes32 internal constant WITHDRAW = keccak256('WITHDRAW');

  /** @dev Contract-related identifiers for various components of the ecosystem */
  bytes32 internal constant CRUTOKEN = keccak256('CRUTOKEN');
  bytes32 internal constant SALES = keccak256('SALES');
  bytes32 internal constant BRANDS = keccak256('BRANDS');
  bytes32 internal constant FEATURES = keccak256('FEATURES');
  bytes32 internal constant PRESALE = keccak256('PRESALE');
  bytes32 internal constant PAYMENTS = keccak256('PAYMENTS');
  bytes32 internal constant WRAPPERS = keccak256('WRAPPERS');
  bytes32 internal constant WHITELIST = keccak256('WHITELIST');
  bytes32 internal constant MEMBERSHIPS = keccak256('MEMBERSHIPS');
  bytes32 internal constant STAKING = keccak256('STAKING');
  bytes32 internal constant REFERRALS = keccak256('REFERRALS');
}
