// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './abstracts/Modifiers.sol';
import './interfaces/IRoles.sol';
import './interfaces/IPayments.sol';
import './interfaces/IMemberships.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/access/IAccessControl.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';

/**
 * @title Payments
 * @notice Optimized payment management for Crutrade ecosystem
 */
contract Payments is
  Initializable,
  UUPSUpgradeable,
  PausableUpgradeable,
  IPayments,
  Modifiers
{
  /* STRUCTS */

  struct FeeConfiguration {
    uint32 buyFeePercentage; // Max 1000 (0.1%)
    uint32 sellFeePercentage; // Max 1000 (0.1%)
    uint32 treasuryPercentage; // Max 100%
    uint32 brandPercentage; // Max 100%
    uint32 stakingPercentage; // Max 100%
    uint32 reserved; // For future use
    bool isActive; // Fee configuration status
  }

  struct TransferOperation {
    address from;
    address to;
    uint256 amount;
    address token;
  }

  /* CONSTANTS */

  uint256 private constant THOUSANDTH_UNIT = 1000;
  uint256 private constant PERCENTAGE_BASE = 100;
  uint256 private constant MAX_FEE_PERCENTAGE = 25_00; // 25%
  uint256 private constant FIAT_FEE_PERCENTAGE = 1; // 1%
  uint256 private constant TOKEN_DECIMALS = 18;
  uint256 private constant SWAP_MULTIPLIER = 10;

  /* STORAGE */

  FeeConfiguration private _feeConfig;

  // Optimized mappings with explicit types
  mapping(uint256 => uint32) private _discounts;
  mapping(bytes32 => uint96) private _serviceFees;

  /* INITIALIZATION */

  constructor() {
    _disableInitializers();
  }

  function initialize(address _roles) public initializer {
    __Pausable_init();
    __UUPSUpgradeable_init();
    __Modifiers_init(_roles);

    // Set default fee configuration
    _feeConfig = FeeConfiguration({
      buyFeePercentage: 25, // 2.5%
      sellFeePercentage: 25, // 2.5%
      treasuryPercentage: 40, // 40%
      brandPercentage: 40, // 40%
      stakingPercentage: 20, // 20%
      reserved: 0,
      isActive: true
    });
  }

  /* CORE FUNCTIONS */

  function distributeRewards(
    address referrer,
    address referral,
    uint256 price
  ) external override onlyDelegatedRole whenNotPaused {
    if (referrer == address(0) || price == 0) return;

    address swapTreasury = roles.getRoleAddress(OWNER);
    address cruToken = roles.getRoleAddress(CRUTOKEN);

    TransferOperation[] memory operations = new TransferOperation[](2);
    operations[0] = TransferOperation({
      from: swapTreasury,
      to: referrer,
      amount: price,
      token: cruToken
    });

    if (referral != address(0)) {
      operations[1] = TransferOperation({
        from: swapTreasury,
        to: referral,
        amount: price,
        token: cruToken
      });
    }

    _executeTransfers(operations);
  }

  function featuredPayment(
    address seller,
    uint256 operation,
    address erc20,
    uint256 directSaleId,
    uint256 amount
  ) external payable whenNotPaused onlyDelegatedRole onlyValidPayment(erc20) {
    if (amount == 0) revert ZeroAmount();

    address from = erc20 == address(0) ? roles.getRoleAddress(FIAT) : seller;

    TransferOperation[] memory operations = new TransferOperation[](1);
    operations[0] = TransferOperation({
      from: from,
      to: roles.getRoleAddress(TREASURY),
      amount: amount,
      token: erc20
    });

    _executeTransfers(operations);
    emit FeaturedPayment(seller, operation, directSaleId, amount);
  }

  function splitServiceFee(
    bytes32 operation,
    address wallet,
    address erc20
  )
    external
    payable
    whenNotPaused
    onlyDelegatedRole
    onlyValidPayment(erc20)
    returns (uint256 serviceFee, uint256 fiatFee)
  {
    serviceFee = _serviceFees[operation];
    if (serviceFee == 0) revert ZeroAmount();

    fiatFee = (serviceFee * FIAT_FEE_PERCENTAGE) / PERCENTAGE_BASE;

    address from = erc20 != address(0) ? wallet : roles.getRoleAddress(FIAT);
    uint256 totalAmount = erc20 != address(0)
      ? serviceFee
      : serviceFee + fiatFee;

    TransferOperation[] memory operations = new TransferOperation[](1);
    operations[0] = TransferOperation({
      from: from,
      to: roles.getRoleAddress(SERVICE),
      amount: totalAmount,
      token: erc20
    });

    _executeTransfers(operations);
    return (serviceFee, fiatFee);
  }

  function splitSaleFees(
    address erc20,
    address seller,
    uint256 price,
    address buyer,
    address brand
  )
    external
    payable
    whenNotPaused
    onlyDelegatedRole
    onlyValidPayment(erc20)
    returns (
      uint256 serviceFee,
      uint256 buyFee,
      uint256 sellFee,
      uint256 treasuryFee,
      uint256 brandFee,
      uint256 stakingFee,
      uint256 fiatFee
    )
  {
    if (!_feeConfig.isActive) revert InvalidFeeConfiguration();
    if (price == 0) revert ZeroAmount();

    // Cache membership contract
    IMemberships memberships = IMemberships(roles.getRoleAddress(MEMBERSHIPS));

    // Calculate base fees with membership discounts
    uint256 buyerDiscount = _discounts[memberships.getMembership(buyer)];
    uint256 sellerDiscount = _discounts[memberships.getMembership(seller)];

    buyFee =
      (price * _feeConfig.buyFeePercentage - (price * buyerDiscount)) /
      THOUSANDTH_UNIT;
    sellFee =
      (price * _feeConfig.sellFeePercentage - (price * sellerDiscount)) /
      THOUSANDTH_UNIT;

    // Validate total fees
    uint256 totalFees = buyFee + sellFee;
    if (totalFees > (price * MAX_FEE_PERCENTAGE) / PERCENTAGE_BASE) {
      revert ExcessiveFees(totalFees, MAX_FEE_PERCENTAGE);
    }

    // Calculate fee distribution
    uint256 feeUnit = totalFees / PERCENTAGE_BASE;
    treasuryFee = feeUnit * _feeConfig.treasuryPercentage;
    brandFee = feeUnit * _feeConfig.brandPercentage;
    stakingFee = feeUnit * _feeConfig.stakingPercentage;

    // Calculate service and fiat fees
    serviceFee = _serviceFees[BUY];
    fiatFee = ((serviceFee + buyFee) * FIAT_FEE_PERCENTAGE) / PERCENTAGE_BASE;

    // Setup transfers
    address from = erc20 != address(0) ? buyer : roles.getRoleAddress(FIAT);
    uint256 earning = price - totalFees;

    TransferOperation[] memory operations = new TransferOperation[](4);
    operations[0] = TransferOperation({
      from: from,
      to: seller,
      amount: earning,
      token: erc20
    });
    operations[1] = TransferOperation({
      from: from,
      to: roles.getRoleAddress(TREASURY),
      amount: treasuryFee,
      token: erc20
    });
    operations[2] = TransferOperation({
      from: from,
      to: brand,
      amount: brandFee,
      token: erc20
    });
    operations[3] = TransferOperation({
      from: from,
      to: roles.getRoleAddress(STAKING),
      amount: stakingFee,
      token: erc20
    });

    _executeTransfers(operations);
    return (
      serviceFee,
      buyFee,
      sellFee,
      treasuryFee,
      brandFee,
      stakingFee,
      fiatFee
    );
  }

  function swap(
    address account,
    address erc20,
    uint256 amount
  ) external payable override onlyDelegatedRole onlyValidPayment(erc20) {
    if (amount == 0) revert ZeroAmount();

    address swapTreasury = roles.getRoleAddress(SWAP);
    address cruToken = roles.getRoleAddress(CRUTOKEN);

    // Calculate token amount with 18 decimals precision
    uint256 tokenAmount = amount * (10 ** TOKEN_DECIMALS) * SWAP_MULTIPLIER;

    TransferOperation[] memory operations = new TransferOperation[](2);
    operations[0] = TransferOperation({
      from: account,
      to: swapTreasury,
      amount: amount,
      token: erc20
    });
    operations[1] = TransferOperation({
      from: swapTreasury,
      to: account,
      amount: tokenAmount,
      token: cruToken
    });

    _executeTransfers(operations);
  }

  /* INTERNAL FUNCTIONS */

  function _executeTransfers(TransferOperation[] memory operations) internal {
    for (uint256 i = 0; i < operations.length; ) {
      TransferOperation memory op = operations[i];
      if (op.amount > 0) {
        if (!IERC20(op.token).transferFrom(op.from, op.to, op.amount)) {
          revert TransferBatch();
        }
      }
      unchecked {
        ++i;
      }
    }
  }

  /* ADMIN FUNCTIONS */

  function setFeeConfiguration(
    uint32 buyFee,
    uint32 sellFee,
    uint32 treasuryFee,
    uint32 brandFee,
    uint32 stakingFee
  ) external onlyRole(OWNER) {
    // Validate fee percentages
    if (treasuryFee + brandFee + stakingFee != PERCENTAGE_BASE) {
      revert InvalidFeeConfiguration();
    }

    _feeConfig = FeeConfiguration({
      buyFeePercentage: buyFee,
      sellFeePercentage: sellFee,
      treasuryPercentage: treasuryFee,
      brandPercentage: brandFee,
      stakingPercentage: stakingFee,
      reserved: 0,
      isActive: true
    });

    emit FeeConfigUpdated(buyFee, sellFee, treasuryFee, brandFee, stakingFee);
  }

  function setServiceFees(
    bytes32[] calldata operations,
    uint96[] calldata fees
  ) external onlyRole(OWNER) {
    //if (operations.length != fees.length) revert InvalidInput();

    for (uint256 i = 0; i < operations.length; ) {
      _serviceFees[operations[i]] = fees[i];
      unchecked {
        ++i;
      }
    }
  }

  function setDiscounts(
    uint256[] calldata membershipIds,
    uint32[] calldata discounts
  ) external onlyRole(OWNER) {
    // if (membershipIds.length != discounts.length) revert InvalidInput();

    for (uint256 i = 0; i < membershipIds.length; ) {
      _discounts[membershipIds[i]] = discounts[i];
      unchecked {
        ++i;
      }
    }
  }

  /* PAUSE/UNPAUSE */

  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  function unpause() external onlyRole(PAUSER) {
    _unpause();
  }

  /* UPGRADE */

  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(UPGRADER) {}
}
