// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ISales Interface
 * @notice Interface defining core functions, structs, and events for an NFT marketplace contract that manages sales operations.
 * @dev Provides the structure and documentation for interacting with sales listings and related fees in the marketplace.
 */

/**
 * @notice Structure for managing date-related parameters in a sale.
 * @param expireListDate The timestamp when the listing expires.
 * @param expireUpcomeDate The timestamp when the sale becomes active.
 */
struct Date {
  uint256 expireListDate;
  uint256 expireUpcomeDate;
}

/**
 * @notice Structure representing the details of a sale.
 * @param id The unique identifier of the sale.
 * @param end The timestamp when the sale ends.
 * @param price The price of the sale in wei.
 * @param start The timestamp when the sale starts.
 * @param seller The address of the seller who listed the item.
 * @param duration The duration of the sale in seconds.
 */
struct Sale {
  uint256 id;
  uint256 end;
  uint256 price;
  uint256 start;
  address seller;
  uint256 duration;
}

/**
 * @notice Input parameters required to create a new sale.
 * @param price The sale price in wei.
 * @param wrapperId The ID of the wrapped NFT.
 * @param durationId The ID referencing a predefined duration setting.
 */
struct SaleInput {
  uint256 price;
  uint256 wrapperId;
  uint256 durationId;
}

/**
 * @notice Basic fee structure for platform service and fiat conversion.
 * @param serviceFee The platform's service fee.
 * @param fiatFee The fee associated with fiat currency conversion.
 */
struct BaseFees {
  uint256 serviceFee;
  uint256 fiatFee;
}

/**
 * @notice Extended fee structure, including additional fees for purchasing.
 * @param base The base platform fees.
 * @param buyFee Fee charged to the buyer.
 * @param sellFee Fee charged to the seller.
 * @param treasuryFee Fee allocated to the treasury.
 * @param brandFee Fee directed to the brand.
 * @param stakingFee Fee designated for staking rewards.
 */
struct BuyFees {
  BaseFees base;
  uint256 buyFee;
  uint256 sellFee;
  uint256 treasuryFee;
  uint256 brandFee;
  uint256 stakingFee;
}

/*//////////////////////////////////////////////////////////////
                          SALE-RELATED ERRORS
//////////////////////////////////////////////////////////////*/

/**
 * @notice Error thrown when an input is unexpectedly empty.
 */
error EmptyInput();

/**
 * @notice Error thrown when an input is invalid or out of acceptable bounds.
 */
error InvalidInput();

/**
 * @notice Error thrown when an invalid address is provided.
 */
error InvalidAddress();

/**
 * @notice Error thrown when array parameters have mismatched lengths.
 */
error MismatchedArrays();

/**
 * @notice Error thrown when a sale has already expired.
 */
error SaleExpired();

/**
 * @notice Error thrown when a sale has not yet started.
 */
error SaleNotStarted();

/**
 * @notice Error thrown when a seller is not whitelisted for a sale.
 */
error SellerNotWhitelisted();

  /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Emitted when items are listed for sale.
   * @param salesIds An array of identifiers for the listed sales.
   * @param dates An array of sale date parameters.
   * @param fees Fee details associated with the listing.
   * @param seller The address of the seller listing the items.
   */
  event List(uint256[] salesIds, Date[] dates, BaseFees fees, address seller);

  /**
   * @notice Emitted when items are purchased.
   * @param salesIds An array of identifiers for the purchased sales.
   * @param fees A detailed breakdown of the fees applied.
   * @param buyer The address of the buyer.
   * @param seller The address of the seller.
   */
  event Buy(uint256[] salesIds, BuyFees fees, address buyer, address seller);

  /**
   * @notice Emitted when listings are withdrawn.
   * @param salesIds An array of identifiers for the withdrawn sales.
   * @param fees Fee information associated with the withdrawal.
   * @param seller The address of the seller withdrawing the listings.
   */
  event Withdraw(uint256[] salesIds, BaseFees fees, address seller);

  /**
   * @notice Emitted when listings are renewed.
   * @param salesIds An array of identifiers for the renewed sales.
   * @param dates New sale date parameters for the renewals.
   * @param fees Fee information associated with the renewal.
   * @param seller The address of the seller renewing the listings.
   */
  event Renew(uint256[] salesIds, Date[] dates, BaseFees fees, address seller);

  /**
   * @notice Emitted when a delay for a specific schedule is updated.
   * @param scheduleId The identifier of the schedule.
   * @param delay The new delay duration for the schedule.
   */
  event DelaySet(uint256 indexed scheduleId, uint256 delay);

  /**
   * @notice Emitted when the timestamp of a schedule is updated.
   * @param scheduleId The identifier of the schedule.
   * @param timestamp The new timestamp for the schedule.
   */
  event ScheduleSet(uint256 indexed scheduleId, uint256 timestamp);

  /**
   * @notice Emitted when the duration of a sale listing is updated.
   * @param durationId The identifier for the duration setting.
   * @param duration The new duration value for the sale.
   */
  event DurationSet(uint256 indexed durationId, uint256 duration);

interface ISales {


  /*//////////////////////////////////////////////////////////////
                                FUNCTIONS
    //////////////////////////////////////////////////////////////*/

  /**
   * @notice Retrieves the sale data associated with a specific sale ID.
   * @param saleId The unique identifier of the sale.
   * @return The `Sale` struct containing the sale data.
   */
  function getSale(uint256 saleId) external view returns (Sale memory);
}
