// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

    // Eventi
    event ReferralCodeAssigned(address indexed referrer, bytes32 indexed code);
    event ReferralLinked(address indexed user, address indexed referrer, bytes32 indexed code);
    event ReferralUsed(address indexed user, address indexed referrer);
    event InfluencerStatusChanged(address indexed referrer, bool status);

    // Errori custom per gas optimization e messaggi più chiari
    error CodeAlreadyAssigned(bytes32 code, address currentOwner);
    error ReferrerAlreadyHasCode(address referrer, bytes32 existingCode);
    error InvalidReferralCode(bytes32 code);
    error ReferralAlreadySet(address user, address existingReferrer);
    error UnauthorizedOperation(address caller, bytes32 code);
    error ZeroAddressProvided();
    error InvalidReferrer(address referrer);
    error SelfReferralNotAllowed(address user);

interface IReferrals {
    function useReferral(address account, uint price) external;
}