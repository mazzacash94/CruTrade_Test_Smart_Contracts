// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Events
event MembershipGranted(address indexed member, uint256 membershipId);
event MembershipRevoked(address indexed member, uint256 membershipId);
event MembershipUpdated(address indexed member, uint256 oldId, uint256 newId);

// Errors
error InvalidMembership(uint256 membershipId);
error MembershipNotFound(address member);
error InvalidMembershipOperation();

interface IMemberships {
    function getMembership(address account) external view returns (uint256);
}