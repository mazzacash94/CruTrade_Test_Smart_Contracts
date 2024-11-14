// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './abstracts/Modifiers.sol';
import './interfaces/IPayments.sol';
import './interfaces/IReferrals.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

contract Referrals is
  Initializable,
  Modifiers,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  IReferrals
{
  using ECDSA for bytes32;

  bytes32 public constant REFERRING_ROLE = keccak256('REFERRING_ROLE');
  bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

  struct Referral {
    bytes32 code;
    address referrer;
    bool isInfluencer;
    uint256 usedCount;
    mapping(address => bool) used;
  }

  mapping(address => Referral) private _referralsData;
  mapping(bytes32 => address) private _referralsCodes;

  event ReferralCodeAssigned(address indexed referrer, bytes32 indexed code);
  event ReferralLinked(
    address indexed user,
    address indexed referrer,
    bytes32 indexed code
  );
  event ReferralUsed(address indexed user, address indexed referrer);
  event InfluencerStatusChanged(address indexed referrer, bool status);

  error CodeAlreadyAssigned(bytes32 code, address currentOwner);
  error ReferrerAlreadyHasCode(address referrer, bytes32 existingCode);
  error InvalidReferralCode(bytes32 code);
  error ReferralAlreadySet(address user, address existingReferrer);
  error UnauthorizedOperation(address caller, bytes32 code);
  error ZeroAddressProvided();
  error InvalidReferrer(address referrer);
  error SelfReferralNotAllowed(address user);

  constructor() {
    _disableInitializers();
  }

  function initialize(address _roles) public initializer {
    if (_roles == address(0)) revert ZeroAddressProvided();
    __Modifiers_init(_roles);
    __Pausable_init();
    __ReentrancyGuard_init();
  }

  /**
   * @notice Creates a new referral code and optionally links it to a referrer
   * @dev Combines the functionality of assignReferralCode and setReferrer
   * @param user Address that will own the referral code
   * @param code The referral code to assign to the user
   * @param referrerCode The referral code of the referrer (optional, can be bytes32(0))
   * @custom:throws CodeAlreadyAssigned if the code is already in use
   * @custom:throws ReferrerAlreadyHasCode if the user already has a referral code
   * @custom:throws InvalidReferralCode if the referrerCode is invalid
   * @custom:throws ZeroAddressProvided if user address is zero
   * @custom:throws SelfReferralNotAllowed if user tries to refer themselves
   */
  function createReferral(
    address user,
    bytes32 code,
    bytes32 referrerCode
  ) external onlyRole(OWNER) whenNotPaused {
    if (user == address(0)) revert ZeroAddressProvided();

    address currentOwner = _referralsCodes[code];
    if (currentOwner != address(0))
      revert CodeAlreadyAssigned(code, currentOwner);

    bytes32 existingCode = _referralsData[user].code;
    if (existingCode != bytes32(0))
      revert ReferrerAlreadyHasCode(user, existingCode);

    // Assign the code
    _referralsCodes[code] = user;
    _referralsData[user].code = code;

    emit ReferralCodeAssigned(user, code);

    // If referrerCode is provided, link the referrer
    if (referrerCode != bytes32(0)) {
      address referrer = _referralsCodes[referrerCode];
      if (referrer == address(0)) revert InvalidReferralCode(referrerCode);
      if (referrer == user) revert SelfReferralNotAllowed(user);

      _referralsData[user].referrer = referrer;
      emit ReferralLinked(user, referrer, referrerCode);
    }
  }

  /**
   * @notice Promotes a referrer to influencer status
   * @dev Only contract owner can promote referrers to influencer status
   * @param referrer Address of the referrer to promote
   * @custom:throws UnauthorizedOperation if the address has no referral code
   * @custom:throws ZeroAddressProvided if referrer address is zero
   */
  function promoteToInfluencer(
    address referrer
  ) external onlyRole(OWNER) whenNotPaused {
    if (referrer == address(0)) revert ZeroAddressProvided();

    Referral storage referral = _referralsData[referrer];
    if (_referralsCodes[referral.code] != referrer)
      revert UnauthorizedOperation(referrer, referral.code);

    referral.isInfluencer = true;
    emit InfluencerStatusChanged(referrer, true);
  }

  /**
   * @dev Processes a referral use
   * @param account Address of the account using the referral
   * @param price Price of the transaction
   * @custom:throws ZeroAddressProvided if account address is zero
   */
  function useReferral(
    address account,
    uint price
  ) external override onlyDelegatedRole whenNotPaused nonReentrant {
    if (account == address(0)) revert ZeroAddressProvided();

    Referral storage referral = _referralsData[account];
    address referrerAddress = referral.referrer;

    if (referrerAddress == address(0)) return;

    Referral storage referrer = _referralsData[referrerAddress];
    bool isFirstUse = !referrer.used[account];

    if (isFirstUse) {
      referrer.used[account] = true;
      referrer.usedCount++;
      IPayments(roles.getRoleAddress(PAYMENTS)).distributeRewards(
        referrerAddress,
        account,
        price
      );
    } else if (referrer.isInfluencer) {
      IPayments(roles.getRoleAddress(PAYMENTS)).distributeRewards(
        referrerAddress,
        address(0),
        price
      );
    }

    emit ReferralUsed(account, referrerAddress);
  }

  /**
   * @notice Allows a referrer to toggle their influencer status
   * @dev Can only be called by the referral code owner
   * @param status New influencer status to set
   * @custom:throws UnauthorizedOperation if caller has no valid referral code
   */
  function setInfluencerStatus(
    bool status
  ) external whenNotPaused nonReentrant {
    Referral storage referral = _referralsData[msg.sender];
    if (_referralsCodes[referral.code] != msg.sender)
      revert UnauthorizedOperation(msg.sender, referral.code);

    referral.isInfluencer = status;
    emit InfluencerStatusChanged(msg.sender, status);
  }

  /**
   * @notice Gets the referral information for a given user
   * @param user Address of the user to query
   * @return code The referral code of the user
   * @return referrer The address of the user's referrer
   * @return isInfluencer Whether the user is an influencer
   * @return usedCount Number of times the user's referral code has been used
   * @custom:throws ZeroAddressProvided if user address is zero
   */
  function getReferralInfo(
    address user
  )
    external
    view
    returns (
      bytes32 code,
      address referrer,
      bool isInfluencer,
      uint256 usedCount
    )
  {
    if (user == address(0)) revert ZeroAddressProvided();

    Referral storage referral = _referralsData[user];
    return (
      referral.code,
      referral.referrer,
      referral.isInfluencer,
      referral.usedCount
    );
  }

  /**
   * @notice Checks if a referral code is valid
   * @param code The code to check
   * @return bool True if the code is valid and assigned to a user
   */
  function isValidReferralCode(bytes32 code) external view returns (bool) {
    return _referralsCodes[code] != address(0);
  }

  /**
   * @notice Pauses all contract functions
   */
  function pause() external onlyRole(PAUSER_ROLE) {
    _pause();
  }

  /**
   * @notice Unpauses all contract functions
   */
  function unpause() external onlyRole(PAUSER_ROLE) {
    _unpause();
  }

  uint256[50] private __gap;
}
