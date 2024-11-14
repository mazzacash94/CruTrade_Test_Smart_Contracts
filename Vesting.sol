// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title CruTrade Vesting Contract
 * @author mazzaca$h - https://linkedin.com/in/mazzacash
 * @notice Advanced vesting system for CruTrade ecosystem with multiple cliff support
 * @dev Manages vesting schedules with multiple cliffs and regular releases
 */
contract Vesting is Ownable {
  using SafeERC20 for IERC20;

  /// @notice Custom errors for better gas efficiency and clearer error messaging
  error ZeroAmount();
  error ZeroAddress();
  error NoTokensToRecover();
  error InvalidCliffPeriods();
  error InvalidArrayLengths();
  error InvalidReleaseSchedule();
  error NoScheduleExists(address beneficiary);
  error ScheduleAlreadyExists(address beneficiary);
  error NoTokensAvailable(address beneficiary, uint256 available);
  error AmountExceedsClaimable(uint256 requested, uint256 available);

  /**
   * @notice Structure defining a cliff period
   * @dev Each cliff has its own duration and release amount
   */
  struct CliffPeriod {
    uint256 duration; // Duration of cliff in seconds
    uint256 releaseAmount; // Amount to release after cliff
    bool released; // Whether cliff amount was released
  }

  /**
   * @notice Structure for regular release schedule configuration
   * @dev Defines the periodic release pattern after cliffs
   */
  struct ReleaseSchedule {
    uint256 interval; // Time between releases
    uint256 amountPerRelease; // Amount per release period
    uint256 numberOfReleases; // Total releases planned
    uint256 releasesIssued; // Number of releases completed
  }

  struct VestingOutputs {
    address beneficiary;
    uint256 vestedAmount;
  }

  /**
   * @notice Complete vesting schedule structure
   * @dev Holds all information about a beneficiary's vesting
   */
  struct VestingSchedule {
    address beneficiary; // Beneficiary address
    uint256 totalAmount; // Total tokens to vest
    uint256 amountClaimed; // Total claimed so far
    uint256 startTime; // Schedule start timestamp
    CliffPeriod[] cliffs; // Array of cliff periods
    ReleaseSchedule release; // Regular release schedule
    bool initialized; // Schedule initialization status
  }

  /// @notice The CruToken being vested
  IERC20 public immutable token;

  address[] public beneficiaries;

  VestingSchedule[] public vestings;

  /// @notice Mapping of beneficiary address to vesting schedule
  mapping(address => VestingSchedule) public vestingSchedules;

  /**
   * @notice Emitted when new vesting schedule is created
   */
  event VestingScheduleCreated(
    address indexed beneficiary,
    uint256 amount,
    uint256 startTime,
    uint256 numberOfCliffs
  );

  /// @notice Modifica della definizione dell'evento per includere i bilanci
  event TokensClaimed(
    address indexed beneficiary,
    uint256 amount,
    uint256 lpBalance, // Balance corrente dei token
    uint256 vestedBalance // Balance ancora in vesting
  );

  /**
   * @notice Emitted when tokens are recovered
   */
  event TokensRecovered(uint256 amount, address indexed recipient);

  /**
   * @notice Contract constructor
   * @param initialOwner Address of the initial owner
   * @param _token Address of the CruToken
   */
  constructor(address initialOwner, address _token) Ownable(initialOwner) {
    if (_token == address(0)) revert ZeroAddress();
    token = IERC20(_token);
  }

function createBatchVestingSchedules(
    address[] calldata _beneficiaries,
    uint256[] calldata _cliffDurations,
    uint256[] calldata _cliffAmounts,
    ReleaseSchedule calldata _releaseSchedule
  ) external onlyOwner {
    // Validation
    if (_beneficiaries.length == 0) revert ZeroAmount();
    if (_cliffDurations.length != _cliffAmounts.length)
      revert InvalidArrayLengths();

    // Calculate total amount needed for all schedules
    uint256 totalAmount = _calculateTotalAmount(
      _cliffAmounts,
      _releaseSchedule
    );
    if (totalAmount == 0) revert ZeroAmount();

    uint256 batchTotal = totalAmount * _beneficiaries.length;

    // Transfer total tokens needed for all schedules
    token.safeTransferFrom(msg.sender, address(this), batchTotal);

    // Pre-resize beneficiaries array
    uint256 currentLength = beneficiaries.length;
    uint256 newLength = currentLength + _beneficiaries.length;
    
    // Extend arrays to accommodate new entries
    for (uint256 i = currentLength; i < newLength; i++) {
        beneficiaries.push();
        vestings.push();
    }

    // Create schedules for each beneficiary
    for (uint256 i = 0; i < _beneficiaries.length; i++) {
      address beneficiary = _beneficiaries[i];

      // Skip if address is zero or schedule exists
      if (beneficiary == address(0)) continue;
      if (vestingSchedules[beneficiary].initialized) continue;

      // Create schedule
      VestingSchedule storage schedule = vestingSchedules[beneficiary];
      schedule.beneficiary = beneficiary;
      schedule.totalAmount = totalAmount;
      schedule.startTime = block.timestamp;
      schedule.release = _releaseSchedule;
      schedule.initialized = true;

      // Set cliff periods
      for (uint256 j = 0; j < _cliffDurations.length; j++) {
        schedule.cliffs.push(
          CliffPeriod({
            duration: _cliffDurations[j],
            releaseAmount: _cliffAmounts[j],
            released: false
          })
        );
      }

      vestings[currentLength + i] = schedule;
      beneficiaries[currentLength + i] = beneficiary;

      emit VestingScheduleCreated(
        beneficiary,
        totalAmount,
        block.timestamp,
        _cliffDurations.length
      );
    }
  }


 function createVestingSchedule(
    address _beneficiary,
    uint256[] calldata _cliffDurations,
    uint256[] calldata _cliffAmounts,
    ReleaseSchedule calldata _releaseSchedule
  ) external onlyOwner {
    // Validation
    if (_beneficiary == address(0)) revert ZeroAddress();
    if (_cliffDurations.length != _cliffAmounts.length)
      revert InvalidArrayLengths();
    if (vestingSchedules[_beneficiary].initialized) {
      revert ScheduleAlreadyExists(_beneficiary);
    }

    // Calculate total amount
    uint256 totalAmount = _calculateTotalAmount(
      _cliffAmounts,
      _releaseSchedule
    );
    if (totalAmount == 0) revert ZeroAmount();

    // Create schedule
    VestingSchedule storage schedule = vestingSchedules[_beneficiary];
    schedule.beneficiary = _beneficiary;
    schedule.totalAmount = totalAmount;
    schedule.startTime = block.timestamp;
    schedule.release = _releaseSchedule;
    schedule.initialized = true;

    // Set cliff periods
    for (uint256 i = 0; i < _cliffDurations.length; i++) {
      schedule.cliffs.push(
        CliffPeriod({
          duration: _cliffDurations[i],
          releaseAmount: _cliffAmounts[i],
          released: false
        })
      );
    }

    // Transfer tokens to contract
    token.safeTransferFrom(msg.sender, address(this), totalAmount);

    vestings.push(schedule);
    beneficiaries.push(_beneficiary);

    emit VestingScheduleCreated(
      _beneficiary,
      totalAmount,
      block.timestamp,
      _cliffDurations.length
    );
  }

  /**
   * @notice Gets total token balance including free and vested tokens
   * @param wallet Address of the wallet to check
   * @return (wallet free balance, vested balance remaining)
   */
  function getVestedBalance(address wallet) external view returns (uint256) {
    VestingSchedule memory schedule = vestingSchedules[wallet];
    return (schedule.totalAmount - schedule.amountClaimed);
  }

  function getAllVestedBalances() external view returns (VestingOutputs[] memory) {
    uint length = vestings.length;
    VestingOutputs[] memory outputs = new VestingOutputs[](length);
    for (uint i; i < length; i++) {
      address beneficiary = beneficiaries[i];
      VestingSchedule memory schedule = vestingSchedules[beneficiary];
      outputs[i].vestedAmount = schedule.totalAmount - schedule.amountClaimed;
      outputs[i].beneficiary = beneficiary;
    }
    return outputs;
  }

  /**
   * @notice Claims tokens on behalf of beneficiary
   * @dev Only owner can execute claims
   */
  function claimTokens(
    address _beneficiary,
    uint256 _amount
  ) external onlyOwner {
    uint256 claimableAmount = getClaimableAmount(_beneficiary);
    if (claimableAmount == 0) {
      revert NoTokensAvailable(_beneficiary, claimableAmount);
    }
    if (_amount > claimableAmount) {
      revert AmountExceedsClaimable(_amount, claimableAmount);
    }

    VestingSchedule storage schedule = vestingSchedules[_beneficiary];
    schedule.amountClaimed += _amount;

    // Update cliff status
    _updateCliffStatus(schedule);

    // Transfer tokens
    token.safeTransfer(_beneficiary, _amount);

    // Emit event with current balances
    emit TokensClaimed(
      _beneficiary,
      _amount,
      token.balanceOf(_beneficiary), // Current token balance
      schedule.totalAmount - schedule.amountClaimed // Remaining vested amount
    );
  }

  /**
   * @notice Calculates claimable tokens for beneficiary
   */
  function getClaimableAmount(
    address _beneficiary
  ) public view returns (uint256 amount) {
    VestingSchedule storage schedule = vestingSchedules[_beneficiary];
    if (!schedule.initialized) return 0;

    uint256 timeElapsed = block.timestamp - schedule.startTime;

    // Check cliff releases
    for (uint256 i = 0; i < schedule.cliffs.length; i++) {
      if (
        timeElapsed >= schedule.cliffs[i].duration &&
        !schedule.cliffs[i].released
      ) {
        amount += schedule.cliffs[i].releaseAmount;
      }
    }

    // Calculate regular releases
    if (timeElapsed > schedule.cliffs[schedule.cliffs.length - 1].duration) {
      uint256 timeAfterCliffs = timeElapsed -
        schedule.cliffs[schedule.cliffs.length - 1].duration;
      uint256 newReleases = timeAfterCliffs / schedule.release.interval;

      if (newReleases > schedule.release.numberOfReleases) {
        newReleases = schedule.release.numberOfReleases;
      }

      newReleases -= schedule.release.releasesIssued;
      amount += newReleases * schedule.release.amountPerRelease;
    }

    return amount;
  }

  /**
   * @notice Updates cliff release status
   * @dev Internal function to track cliff releases
   */
  function _updateCliffStatus(VestingSchedule storage _schedule) internal {
    uint256 timeElapsed = block.timestamp - _schedule.startTime;

    for (uint256 i = 0; i < _schedule.cliffs.length; i++) {
      if (
        timeElapsed >= _schedule.cliffs[i].duration &&
        !_schedule.cliffs[i].released
      ) {
        _schedule.cliffs[i].released = true;
      }
    }

    // Update regular releases
    if (timeElapsed > _schedule.cliffs[_schedule.cliffs.length - 1].duration) {
      uint256 timeAfterCliffs = timeElapsed -
        _schedule.cliffs[_schedule.cliffs.length - 1].duration;
      uint256 newReleases = timeAfterCliffs / _schedule.release.interval;
      if (newReleases > _schedule.release.numberOfReleases) {
        newReleases = _schedule.release.numberOfReleases;
      }
      _schedule.release.releasesIssued = newReleases;
    }
  }

  /**
   * @notice Calculates total tokens for schedule
   */
  function _calculateTotalAmount(
    uint256[] calldata _cliffAmounts,
    ReleaseSchedule calldata _releaseSchedule
  ) internal pure returns (uint256 total) {
    for (uint256 i = 0; i < _cliffAmounts.length; i++) {
      total += _cliffAmounts[i];
    }
    total +=
      _releaseSchedule.amountPerRelease *
      _releaseSchedule.numberOfReleases;
    return total;
  }

  /**
   * @notice Emergency token recovery
   * @dev Only owner can recover tokens
   */
  function recoverTokens() external onlyOwner {
    uint256 balance = token.balanceOf(address(this));
    if (balance == 0) revert NoTokensToRecover();

    token.safeTransfer(msg.sender, balance);

    emit TokensRecovered(balance, msg.sender);
  }
}
