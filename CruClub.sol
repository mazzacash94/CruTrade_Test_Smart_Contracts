// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Pausable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';

/*
========================================================================================
      ______                        ______   __            __       
     /      \                      /      \ |  \          |  \      
    |  $$$$$$\  ______   __    __ |  $$$$$$\| $$ __    __ | $$____  
    | $$   \$$ /      \ |  \  |  \| $$   \$$| $$|  \  |  \| $$    \ 
    | $$      |  $$$$$$\| $$  | $$| $$      | $$| $$  | $$| $$$$$$$\
    | $$   __ | $$   \$$| $$  | $$| $$   __ | $$| $$  | $$| $$  | $$
    | $$__/  \| $$      | $$__/ $$| $$__/  \| $$| $$__/ $$| $$__/ $$
     \$$    $$| $$       \$$    $$ \$$    $$| $$ \$$    $$| $$    $$
      \$$$$$$  \$$        \$$$$$$   \$$$$$$  \$$  \$$$$$$  \$$$$$$$ 

========================================================================================

    @title        CruClub   - Membership Staking Protocol
    @custom:web   CruTrade  - https://crutrade.io
    @author       mazzaca$h - https://linkedin.com/in/mazzacash
 
    @notice       Revolutionary membership staking protocol where CRU tokens
                  transform into sCRU - your key to exclusive CruTrade benefits.
                  • Dynamic rate mechanism ensures fair value distribution
                  • sCRU tokens represent your CruTrade membership level
                  • Unlock premium features based on your staking data
                  • Time-locked unstaking protects protocol stability
 
    @dev          Security Features:
                  • Signature verification for stake, unstake, and claim operations
                  • Reentrancy protection on all state-changing functions
                  • Pausable functionality for emergency scenarios
                  • Secure token recovery system for external tokens
                  • Protected redemption rate mechanism

========================================================================================
 */
contract CruClub is ERC20, Ownable, Pausable {
  /* ========== LIBRARIES ========== */

  using ECDSA for bytes32;
  using SafeERC20 for IERC20;

  /* ========== STRUCTS ========== */

  /**
   * @dev Stores unstaking data details for a user
   * @param end Timestamp when data becomes claimable
   * @param start Timestamp when unstaking was initiated
   * @param amount Amount of CRU tokens being unstaked
   */
  struct Unstake {
    uint256 end;
    uint256 start;
    uint256 amount;
  }

  /* ========== STATE VARIABLES ========== */

  /// @dev CRU token contract reference
  IERC20 private immutable _cruToken;

  /// @dev Precision factor for rate calculations
  uint256 private constant PRECISION = 1e18;

  /// @dev Duration of unstaking delay period
  uint256 private _delay = 1 minutes;

  /// @dev Total amount of CRU tokens staked
  uint256 private _totalStaked;

  /// @dev Total amount of CRU tokens in unstaking
  uint256 private _unstakeSupply;

  /// @dev Current CRU/sCRU conversion rate
  uint256 private _redemptionRate;

  /// @dev Maps user address to their unstaking data
  mapping(address => Unstake) private _unstaked;

  /// @dev Maps signature hash to usage status for replay protection
  mapping(bytes32 => bool) private _usedHashes;

  /* ========== ERRORS ========== */

  /// @dev Amount provided is zero
  error ZeroAmount(uint256 amount);

  /// @dev Address provided is zero address
  error ZeroAddress(address account);

  /// @dev Hash has already been used
  error HashAlreadyUsed(bytes32 hash);

  /// @dev No tokens available to claim
  error NothingToClaim(address account);

  /// @dev Math operation failed
  error MathError(string operation, uint256 value);

  /// @dev Insufficient balance for operation
  error InsufficientBalance(
    address account,
    uint256 requested,
    uint256 balance
  );

  /// @dev Unstaking period not yet complete
  error StillLocked(uint256 unlockTime, uint256 currentTime);

  /// @dev Recovery amount exceeds available balance
  error ExceedsRecoverableAmount(uint256 requested, uint256 available);

  /// @dev Invalid signature provided
  error InvalidSignature(address account, bytes32 hash, bytes signature);

  /* ========== EVENTS ========== */

  /**
   * @dev Emitted when tokens are staked
   * @param account User address
   * @param cruAmount Amount of CRU staked
   * @param sCruAmount Amount of sCRU minted
   * @param redemptionRate Current redemption rate
   */
  event Staked(
    address indexed account,
    uint256 cruAmount,
    uint256 sCruAmount,
    uint256 redemptionRate
  );

  /**
   * @dev Emitted when tokens are unstaked
   * @param account User address
   * @param end Unlock timestamp
   * @param start Start timestamp
   * @param cruAmount CRU amount unstaked
   * @param sCruAmount sCRU amount burned
   * @param redemptionRate Current redemption rate
   */
  event Unstaked(
    address indexed account,
    uint256 end,
    uint256 start,
    uint256 cruAmount,
    uint256 sCruAmount,
    uint256 redemptionRate
  );

  /**
   * @dev Emitted when CRU tokens are airdropped
   * @param amount Amount of CRU tokens added
   */
  event Airdropped(uint256 amount);

  /**
   * @dev Emitted when unstaking delay is updated
   * @param newDelay New delay duration
   */
  event DelayUpdated(uint256 newDelay);

  /**
   * @dev Emitted when unstaked tokens are claimed
   * @param account User address
   * @param amount Amount claimed
   */
  event Claimed(address indexed account, uint256 amount);

  /**
   * @dev Emitted when tokens are recovered
   * @param token Token address
   * @param amount Amount recovered
   */
  event TokensRecovered(address indexed token, uint256 amount);

  /**
   * @dev Emitted when redemption rate is updated
   * @param newRate New redemption rate
   * @param timestamp Time of update
   */
  event RedemptionRateUpdated(uint256 newRate, uint256 timestamp);

  /* ========== CONSTRUCTOR ========== */

  /**
   * @notice Initializes protocol with CRU token and owner
   * @param cru CRU token address
   * @param initialOwner Contract owner address
   */
  constructor(
    address cru,
    address initialOwner
  ) ERC20('CruClub', 'sCRU') Ownable(initialOwner) {
    require(cru != address(0), ZeroAddress(cru));
    _cruToken = IERC20(cru);
    _redemptionRate = PRECISION; // Set 1:1 ratio
  }

  /* ========== MODIFIERS ========== */

  /**
   * @dev Verifies the signature of a message
   * @param wallet Address of the signer
   * @param hash Hash of the message
   * @param signature Signature to verify
   */
  modifier verifySignature(
    address wallet,
    bytes32 hash,
    bytes calldata signature
  ) {
    require(!_usedHashes[hash], HashAlreadyUsed(hash));
    address recoveredSigner = ECDSA.recover(
      MessageHashUtils.toEthSignedMessageHash(hash),
      signature
    );
    require(
      recoveredSigner == wallet,
      InvalidSignature(wallet, hash, signature)
    );
    _usedHashes[hash] = true;
    _;
  }

  /* ========== VIEWS ========== */

  /**
   * @notice Gets CRU token contract
   * @return IERC20 CRU token interface
   */
  function getCruToken() external view returns (IERC20) {
    return _cruToken;
  }

  /**
   * @notice Gets current unstaking delay
   * @return uint256 Delay in seconds
   */
  function getDelay() external view returns (uint256) {
    return _delay;
  }

  /**
   * @notice Gets total CRU staked
   * @return uint256 Total staked amount
   */
  function getTotalStaked() external view returns (uint256) {
    return _totalStaked;
  }

  /**
   * @notice Gets total CRU in unstaking
   * @return uint256 Total unstaking amount
   */
  function getUnstakeSupply() external view returns (uint256) {
    return _unstakeSupply;
  }

  /**
   * @notice Gets current redemption rate
   * @return uint256 CRU/sCRU conversion rate
   */
  function getRedemptionRate() external view returns (uint256) {
    return _redemptionRate;
  }

  /**
   * @notice Gets user's unstaking data
   * @param account Address to query
   * @return Unstake Unstaking data details
   */
  function getUnstake(address account) external view returns (Unstake memory) {
    return _unstaked[account];
  }

  /**
   * @notice Gets user's claimable amount
   * @param account Address to query
   * @return uint256 Claimable amount
   */
  function getClaimableAmount(address account) external view returns (uint256) {
    return _unstaked[account].amount;
  }

  /**
   * @notice Gets total CRU (to unstake & rewards)
   * @param account Address to query
   * @return uint256 Total of CRU to unstake and rewards
   */
  function getLiveStakingValue(address account) public view returns (uint256) {
    return (balanceOf(account) * _redemptionRate) / PRECISION;
  }

  /**
   * @notice Gets available CRU for staking
   * @return uint256 Available CRU balance
   */
  function getStakingSupply() public view returns (uint256) {
    return _cruToken.balanceOf(address(this)) - _unstakeSupply;
  }

  /**
   * @notice Gets CRU value of user's sCRU
   * @param account Address to query
   * @return uint256 CRU value
   */
  function getCruValue(address account) external view returns (uint256) {
    return (balanceOf(account) * _redemptionRate) / PRECISION;
  }

/**
   * @notice Calculates sCRU amount from CRU amount
   * @param amount Amount of CRU tokens
   * @return uint256 Equivalent amount of sCRU tokens
   */
  function getCruToSCru(uint256 amount) external view returns (uint256) {
    require(amount != 0, ZeroAmount(amount));
    uint256 sCruAmount = (amount * PRECISION) / _redemptionRate;
    require(sCruAmount != 0, MathError('sCRU calculation', sCruAmount));
    return sCruAmount;
  }

  /* ========== INTERNAL ========== */

  /**
   * @dev Updates redemption rate based on protocol state
   * @notice Updates CRU/sCRU conversion rate based on current reserves
   */
  function _updateRedemptionRate() private {
    uint256 supply = totalSupply();
    require(supply != 0, MathError('Division by zero', supply));

    uint256 newRate = (getStakingSupply() * PRECISION) / supply;
    require(newRate != 0, MathError('Rate calculation', newRate));

    _redemptionRate = newRate;
    emit RedemptionRateUpdated(newRate, block.timestamp);
  }

  /* ========== MUTATIVE ========== */

  /**
   * @notice Stakes CRU tokens for sCRU
   * @param hash Message hash
   * @param signature Valid signature from account
   * @param account Address to stake for
   * @param amount CRU amount to stake
   */
  function stake(
    bytes32 hash,
    bytes calldata signature,
    address account,
    uint256 amount
  )
    external
    onlyOwner
    whenNotPaused
    verifySignature(account, hash, signature)
  {
    require(amount != 0, ZeroAmount(amount));
    require(account != address(0), ZeroAddress(account));

    uint256 sCruAmount = (amount * PRECISION) / _redemptionRate;
    require(sCruAmount != 0, MathError('sCRU calculation', sCruAmount));

    _totalStaked += amount;

    _cruToken.safeTransferFrom(account, address(this), amount);
    _mint(account, sCruAmount);

    emit Staked(account, amount, balanceOf(account), _redemptionRate);
  }

  /**
   * @notice Initiates unstaking process
   * @param hash Message hash
   * @param signature Valid signature from account
   * @param account Address to unstake for
   * @param sCruAmount sCRU amount to unstake
   */
  function unstake(
    bytes32 hash,
    bytes calldata signature,
    address account,
    uint256 sCruAmount
  )
    external
    onlyOwner
    whenNotPaused
    verifySignature(account, hash, signature)
  {
    require(sCruAmount != 0, ZeroAmount(sCruAmount));
    require(
      sCruAmount <= balanceOf(account),
      InsufficientBalance(account, sCruAmount, balanceOf(account))
    );

    uint256 cruAmount = (sCruAmount * _redemptionRate) / PRECISION;
    require(cruAmount != 0, MathError('CRU calculation', cruAmount));

    uint256 start = block.timestamp;
    uint256 end = start + _delay;

    _unstaked[account].end = end;
    _unstaked[account].start = start;
    _unstaked[account].amount = cruAmount;
    _unstakeSupply += cruAmount;

    _burn(account, sCruAmount);

    emit Unstaked(account, end, start, cruAmount, sCruAmount, _redemptionRate);
  }

  /**
   * @notice Claims unstaked tokens after delay
   * @param hash Message hash
   * @param signature Valid signature from account
   * @param account Address to claim for
   */
  function claim(
    bytes32 hash,
    bytes calldata signature,
    address account
  )
    external
    onlyOwner
    whenNotPaused
    verifySignature(account, hash, signature)
  {
    Unstake storage data = _unstaked[account];
    require(data.amount != 0, NothingToClaim(account));
    require(
      block.timestamp >= data.end,
      StillLocked(data.end, block.timestamp)
    );

    uint256 amount = data.amount;
    _unstakeSupply -= amount;
    delete _unstaked[account];

    _cruToken.safeTransfer(account, amount);
    emit Claimed(account, amount);
  }

  /* ========== RECOVERY ========== */

  /**
   * @notice Recovers tokens from contract
   * @dev Recovers only excess CRU tokens, full balance for others
   * @param tokenAddress Token to recover
   * @param amount Amount to recover
   */
  function recoverERC20(
    address tokenAddress,
    uint256 amount
  ) external onlyOwner {
    require(amount != 0, ZeroAmount(amount));

    if (tokenAddress == address(_cruToken)) {
      uint256 available = _cruToken.balanceOf(address(this)) -
        (_totalStaked + _unstakeSupply);
      require(amount <= available, ExceedsRecoverableAmount(amount, available));
    }

    IERC20(tokenAddress).safeTransfer(owner(), amount);
    emit TokensRecovered(tokenAddress, amount);
  }

  /* ========== ADMIN ========== */

  /**
   * @notice Forces redemption rate update
   */
  function updateRedemptionRate() external onlyOwner {
    _updateRedemptionRate();
  }

  /**
   * @notice Sets unstaking delay period
   * @param newDelay New delay in seconds
   */
  function setDelay(uint256 newDelay) external onlyOwner {
    _delay = newDelay;
    emit DelayUpdated(newDelay);
  }

  /**
   * @notice Adds CRU tokens to staking pool
   * @param amount Amount to add
   */
  function airdrop(uint256 amount) external onlyOwner {
    require(amount != 0, ZeroAmount(amount));
    _cruToken.safeTransferFrom(msg.sender, address(this), amount);
    _updateRedemptionRate();
    emit Airdropped(amount);
  }

  /**
   * @notice Pauses all contract operations
   */
  function pause() external onlyOwner {
    _pause();
  }

  /**
   * @notice Resumes contract operations
   */
  function unpause() external onlyOwner {
    _unpause();
  }
}
