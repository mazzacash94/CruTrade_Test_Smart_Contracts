// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";

// Events
event RolesSet(address indexed roles);
event PaymentRoleGranted(address indexed payment);
event PaymentRoleRevoked(address indexed payment);
event DelegateRoleGranted(address indexed _contract);
event DelegateRoleRevoked(address indexed _contract);

// Errors
error InvalidRole(bytes32 role);
error InvalidContract(address contractAddress);

interface IRoles is IAccessControl {
    function hasDelegateRole(address _contract) external view returns (bool);
    function hasPaymentRole(address _contract) external view returns (bool);
    function getRoleAddress(bytes32 role) external view returns (address);
}