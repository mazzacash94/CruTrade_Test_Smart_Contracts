// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './abstracts/Modifiers.sol';
import './interfaces/ISales.sol';
import './interfaces/IPayments.sol';
import './interfaces/IWrappers.sol';
import './interfaces/IReferrals.sol';
import './interfaces/IMemberships.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/access/IAccessControl.sol';
import '@openzeppelin/contracts/utils/cryptography/ECDSA.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

/**
 * @title Sales Contract
 * @notice Manages NFT marketplace operations including listing, buying, withdrawing and renewing
 * @custom:security-contact security@example.com
 */
contract Sales is
  Initializable,
  UUPSUpgradeable,
  PausableUpgradeable,
  ReentrancyGuardUpgradeable,
  Modifiers
{
  using EnumerableSet for EnumerableSet.UintSet;

  /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

  /// @notice Collection of sales for a specific SKU
  struct SaleCollection {
    mapping(uint256 => Sale) sales;
    EnumerableSet.UintSet saleIds;
  }

  /// @dev Core storage mappings
  mapping(uint256 => Sale) private _salesById;
  mapping(uint256 => uint256) private _delays;
  mapping(uint256 => uint256) private _durations;
  mapping(uint256 => uint256) private _schedules;
  mapping(uint256 => uint256) private _priorities;
  mapping(bytes32 => SaleCollection) private _salesByCollection;

  /// @dev Schedule control variables
  uint256 private _scheduleDay;
  uint256 private _delayId;

  /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/

  /// @notice Contract initializer
  /// @param _roles Address of the Roles contract
  function initialize(address _roles) external initializer {
    __Pausable_init();
    __UUPSUpgradeable_init();
    __ReentrancyGuard_init();
    __Modifiers_init(_roles);

    // Initialize schedule parameters
    _scheduleDay = 6;
    _delays[0] = _delays[1] = 2 minutes;
    _durations[0] = 5 minutes;
    _priorities[0] = 15 seconds;
  }

  /*//////////////////////////////////////////////////////////////
                              CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Lists NFTs for sale
  /// @dev Processes single or batch listings with optimized gas usage
  function list(
    address seller,
    bytes32 hash,
    bytes calldata signature,
    address erc20,
    SaleInput[] calldata salesInputs
  )
    external
    whenNotPaused
    nonReentrant
    onlyRole(LISTER)
    onlyWhitelisted(seller)
    checkSignature(seller, hash, signature)
  {
    uint256 length = salesInputs.length;
    if (length == 0) revert EmptyInput();

    // Cache contracts and common values
    IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));
    IPayments payments = IPayments(roles.getRoleAddress(PAYMENTS));

    uint256 start = _calculateStartTime();
    uint256 duration = _getDuration(0);
    uint256 end = start + duration;

    // Initialize return data
    Date[] memory dates = new Date[](length);
    uint256[] memory salesIds = new uint256[](length);
    BaseFees memory fees;

    // Process listings
    for (uint256 i; i < length; ) {
      _processSaleListing(
        seller,
        salesInputs[i],
        wrappers,
        payments,
        erc20,
        start,
        end,
        duration,
        salesIds,
        dates,
        fees,
        i
      );
      unchecked {
        ++i;
      }
    }

    emit List(salesIds, dates, fees, seller);
  }

  /// @notice Executes NFT purchases
  function buy(
    address buyer,
    bytes32 hash,
    bytes calldata signature,
    address erc20,
    uint256[] calldata salesIds
  )
    external
    whenNotPaused
    nonReentrant
    onlyRole(BUYER)
    onlyWhitelisted(buyer)
    checkSignature(buyer, hash, signature)
  {
    if (salesIds.length == 0) revert EmptyInput();

    // Cache contracts
    IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));
    IPayments payments = IPayments(roles.getRoleAddress(PAYMENTS));
    IMemberships memberships = IMemberships(roles.getRoleAddress(MEMBERSHIPS));
    IWhitelist whitelist = IWhitelist(roles.getRoleAddress(WHITELIST));
    IBrands brands = IBrands(roles.getRoleAddress(BRANDS));

    BuyFees memory fees;
    address seller;
    address brand;

    uint256 membershipId = memberships.getMembership(buyer);
    uint256 buyerPriority = _priorities[membershipId];

    for (uint256 i; i < salesIds.length; ) {
      _processPurchase(
        buyer,
        salesIds[i],
        wrappers,
        payments,
        whitelist,
        brands,
        buyerPriority,
        erc20,
        fees,
        seller,
        brand
      );
      unchecked {
        ++i;
      }
    }

    emit Buy(salesIds, fees, buyer, seller);
  }

  /// @notice Withdraws listed NFTs
  function withdraw(
    address seller,
    bytes32 hash,
    bytes calldata signature,
    address erc20,
    uint256[] calldata salesIds
  )
    external
    whenNotPaused
    nonReentrant
    onlyRole(WITHDRAWER)
    onlyWhitelisted(seller)
    checkSignature(seller, hash, signature)
  {
    if (salesIds.length == 0) revert EmptyInput();

    IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));
    IPayments payments = IPayments(roles.getRoleAddress(PAYMENTS));

    BaseFees memory fees;

    for (uint256 i; i < salesIds.length; ) {
      _processWithdrawal(seller, salesIds[i], wrappers, payments, erc20, fees);
      unchecked {
        ++i;
      }
    }

    emit Withdraw(salesIds, fees, seller);
  }

  /// @notice Renews existing listings
  function renew(
    address seller,
    bytes32 hash,
    bytes calldata signature,
    address erc20,
    uint256[] calldata salesIds
  )
    external
    whenNotPaused
    nonReentrant
    onlyRole(RENEWER)
    onlyWhitelisted(seller)
    checkSignature(seller, hash, signature)
  {
    if (salesIds.length == 0) revert EmptyInput();

    IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));
    IPayments payments = IPayments(roles.getRoleAddress(PAYMENTS));

    uint256 length = salesIds.length;
    Date[] memory dates = new Date[](length);
    BaseFees memory fees;

    for (uint256 i; i < length; ) {
      bytes32 collection = wrappers.getData(salesIds[i]).sku;
      Sale storage sale = _salesByCollection[collection].sales[salesIds[i]];

      if (sale.seller != seller) revert NotOwner(seller, sale.seller);

      (uint256 serviceFee, uint256 fiatFee) = payments.splitServiceFee(
        RENEW,
        seller,
        erc20
      );

      unchecked {
        fees.serviceFee += serviceFee;
        fees.fiatFee += fiatFee;

        uint256 end = block.timestamp + sale.duration;
        sale.end = end;

        dates[i] = Date({
          expireListDate: end,
          expireUpcomeDate: block.timestamp
        });

        ++i;
      }
    }

    emit Renew(salesIds, dates, fees, seller);
  }

  /*//////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @dev Processes single sale listing
  function _processSaleListing(
    address seller,
    SaleInput memory input,
    IWrappers wrappers,
    IPayments payments,
    address erc20,
    uint256 start,
    uint256 end,
    uint256 duration,
    uint256[] memory salesIds,
    Date[] memory dates,
    BaseFees memory fees,
    uint256 index
  ) private {
    // Validate ownership
    if (IERC721(address(wrappers)).ownerOf(input.wrapperId) != seller) {
      revert NotOwner(
        seller,
        IERC721(address(wrappers)).ownerOf(input.wrapperId)
      );
    }

    bytes32 collection = wrappers.getData(input.wrapperId).sku;

    Sale memory sale = Sale({
      price: input.price,
      seller: seller,
      end: end,
      duration: duration,
      start: start,
      id: input.wrapperId
    });

    _salesById[input.wrapperId] = sale;
    _salesByCollection[collection].sales[input.wrapperId] = sale;
    _salesByCollection[collection].saleIds.add(input.wrapperId);

    salesIds[index] = input.wrapperId;
    dates[index] = Date({ expireListDate: end, expireUpcomeDate: start });

    (uint256 serviceFee, uint256 fiatFee) = payments.splitServiceFee(
      LIST,
      seller,
      erc20
    );

    unchecked {
      fees.serviceFee += serviceFee;
      fees.fiatFee += fiatFee;
    }

    wrappers.marketplaceTransfer(seller, address(this), input.wrapperId);
  }

  /// @dev Processes single purchase
  function _processPurchase(
    address buyer,
    uint256 saleId,
    IWrappers wrappers,
    IPayments payments,
    IWhitelist whitelist,
    IBrands brands,
    uint256 buyerPriority,
    address erc20,
    BuyFees memory fees,
    address seller,
    address brand
  ) private {
    Wrapper memory wrapper = wrappers.getData(saleId);
    Sale storage sale = _salesByCollection[wrapper.sku].sales[saleId];
    seller = sale.seller;
    brand = brands.getBrand(wrapper.brandId).owner;

    if (block.timestamp > sale.end) revert SaleExpired();
    if (!whitelist.isWhitelisted(seller)) revert SellerNotWhitelisted();
    if (block.timestamp < sale.start + buyerPriority) revert SaleNotStarted();

    (
      uint256 serviceFee,
      uint256 buyFee,
      uint256 sellFee,
      uint256 treasuryFee,
      uint256 brandFee,
      uint256 stakingFee,
      uint256 fiatFee
    ) = payments.splitSaleFees(erc20, seller, sale.price, buyer, brand);

    unchecked {
      fees.base.serviceFee += serviceFee;
      fees.base.fiatFee += fiatFee;
      fees.buyFee += buyFee;
      fees.sellFee += sellFee;
      fees.treasuryFee += treasuryFee;
      fees.brandFee += brandFee;
      fees.stakingFee += stakingFee;
    }

    wrappers.marketplaceTransfer(address(this), buyer, saleId);

    delete _salesByCollection[wrapper.sku].sales[saleId];
    _salesByCollection[wrapper.sku].saleIds.remove(saleId);
  }

  /// @dev Processes single withdrawal
  function _processWithdrawal(
    address seller,
    uint256 saleId,
    IWrappers wrappers,
    IPayments payments,
    address erc20,
    BaseFees memory fees
  ) private {
    bytes32 collection = wrappers.getData(saleId).sku;
    Sale storage sale = _salesByCollection[collection].sales[saleId];

    if (sale.seller != seller) revert NotOwner(seller, sale.seller);

    (uint256 serviceFee, uint256 fiatFee) = payments.splitServiceFee(
      WITHDRAW,
      seller,
      erc20
    );

    unchecked {
      fees.serviceFee += serviceFee;
      fees.fiatFee += fiatFee;
    }

    wrappers.marketplaceTransfer(address(this), seller, saleId);

    delete _salesByCollection[collection].sales[saleId];
    _salesByCollection[collection].saleIds.remove(saleId);
  }

  /// @dev Calculates listing start time
  function _calculateStartTime() private view returns (uint256) {
    uint256 scheduleTimestamp = _schedules[0];

    if (scheduleTimestamp == 0) {
      return block.timestamp;
    }

    return _getNextScheduleDay(scheduleTimestamp);
  }

  /// @dev Calculates next schedule day
  function _getNextScheduleDay(
    uint256 scheduleTimestamp
  ) private view returns (uint256) {
    if (_scheduleDay == 0) return block.timestamp + 10 minutes;

    uint256 current = block.timestamp;
    uint256 timestamp = current - (current % 1 days);
    uint256 dayOfWeek = (timestamp / 1 days + 4) % 7;

    if (dayOfWeek == _scheduleDay) {
      return timestamp + 7 days;
    }

    uint256 daysUntilNext = (_scheduleDay + 7 - dayOfWeek) % 7;
    return timestamp + daysUntilNext * 1 days;
  }

  /// @dev Returns duration by ID
  function _getDuration(uint256 durationId) private view returns (uint256) {
    return _durations[durationId];
  }

  /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Returns sale data by ID
  function getSale(uint256 saleId) external view returns (Sale memory) {
    return _salesById[saleId];
  }

  /// @notice Returns all sales for a collection
  function getSalesByCollection(
    bytes32 sku
  ) external view returns (Sale[] memory) {
    uint256 length = _salesByCollection[sku].saleIds.length();
    Sale[] memory sales = new Sale[](length);

    for (uint256 i; i < length; ) {
      uint256 saleId = _salesByCollection[sku].saleIds.at(i);
      sales[i] = _salesByCollection[sku].sales[saleId];
      unchecked {
        ++i;
      }
    }

    return sales;
  }

  /// @notice Returns sale dates for user
  function getSaleDates(
    address user,
    uint256[] calldata salesIds
  ) external view returns (uint256, uint256) {
    if (salesIds.length == 0) revert EmptyInput();

    uint256 membershipId = IMemberships(roles.getRoleAddress(MEMBERSHIPS))
      .getMembership(user);
    uint256 priority = _priorities[membershipId];

    Sale memory sale = _salesById[salesIds[0]];
    return (sale.start + priority, sale.end);
  }

  /// @notice Returns sale IDs for a collection
  function getSalesIdsByCollection(
    bytes32 sku
  ) external view returns (uint256[] memory) {
    return _salesByCollection[sku].saleIds.values();
  }

  /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Sets schedule timestamps
  function setSchedules(
    uint256[] calldata scheduleIds,
    uint256[] calldata timestamps
  ) external onlyRole(OWNER) {
    if (scheduleIds.length != timestamps.length) revert MismatchedArrays();

    for (uint256 i; i < scheduleIds.length; ) {
      _schedules[scheduleIds[i]] = timestamps[i];
      emit ScheduleSet(scheduleIds[i], timestamps[i]);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Sets sale durations
  function setDurations(
    uint256[] calldata durationIds,
    uint256[] calldata durations
  ) external onlyRole(OWNER) {
    if (durationIds.length != durations.length) revert MismatchedArrays();

    for (uint256 i; i < durationIds.length; ) {
      _durations[durationIds[i]] = durations[i];
      emit DurationSet(durationIds[i], durations[i]);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Sets time delays
  function setDelays(
    uint256[] calldata scheduleIds,
    uint256[] calldata delays
  ) external onlyRole(OWNER) {
    if (scheduleIds.length != delays.length) revert MismatchedArrays();

    for (uint256 i; i < scheduleIds.length; ) {
      _delays[scheduleIds[i]] = delays[i];
      emit DelaySet(scheduleIds[i], delays[i]);
      unchecked {
        ++i;
      }
    }
  }

  /// @notice Sets schedule day
  function setScheduleDay(uint256 newScheduleDay) external onlyRole(OWNER) {
    if (newScheduleDay >= 7) revert InvalidInput();
    _scheduleDay = newScheduleDay;
  }

  /*//////////////////////////////////////////////////////////////
                            GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /// @notice Pauses contract operations
  function pause() external onlyRole(PAUSER) {
    _pause();
  }

  /// @notice Unpauses contract operations
  function unpause() external onlyRole(PAUSER) {
    _unpause();
  }

  /// @notice Authorizes contract upgrade
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(UPGRADER) {}

  /*//////////////////////////////////////////////////////////////
                            GETTERS
    //////////////////////////////////////////////////////////////*/

  /// @notice Gets current schedule day
  function getScheduleDay() external view returns (uint256) {
    return _scheduleDay;
  }

  /// @notice Gets delay for a schedule
  function getDelay(uint256 scheduleId) external view returns (uint256) {
    return _delays[scheduleId];
  }

  /// @notice Gets duration for an ID
  function getDuration(uint256 durationId) external view returns (uint256) {
    return _durations[durationId];
  }

  /// @notice Gets schedule timestamp
  function getSchedule(uint256 scheduleId) external view returns (uint256) {
    return _schedules[scheduleId];
  }

  /// @notice Gets next schedule day timestamp
  function getNextScheduleDay() external view returns (uint256) {
    uint256 current = block.timestamp;
    if (_scheduleDay == 0) {
      return current + 10 minutes;
    }

    uint256 timestamp = current - (current % 1 days);
    uint256 dayOfWeek = (timestamp / 1 days + 4) % 7;

    if (dayOfWeek == _scheduleDay) {
      return timestamp + 7 days;
    }

    uint256 daysUntilNext = (_scheduleDay + 7 - dayOfWeek) % 7;
    return timestamp + daysUntilNext * 1 days;
  }

  /*//////////////////////////////////////////////////////////////
                            EMERGENCY FUNCTIONS  
    //////////////////////////////////////////////////////////////*/

  /// @notice Emergency withdrawal of stuck tokens
  /// @dev Only callable by contract owner
  function emergencyWithdraw(
    address token,
    address recipient,
    uint256 amount
  ) external onlyRole(OWNER) {
    if (token == address(0)) revert InvalidAddress();
    if (recipient == address(0)) revert InvalidAddress();

    //IERC721(token).transfer(recipient, amount);
  }
}
