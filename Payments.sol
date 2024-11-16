// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/IRoles.sol";
import "./abstracts/Modifiers.sol";
import "./interfaces/IPayments.sol";
import "./interfaces/IMemberships.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Payments is 
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    IPayments,
    Modifiers 
{
    struct ServiceFee {
        bytes32 operation;
        uint256 serviceFees;
        uint256 fiatFees;
    }

    struct SaleFees {
        uint256 buyFee;
        uint256 sellFee;
        uint256 treasuryFee;
        uint256 brandFee;
        uint256 stakingFee;
        ServiceFee serviceFee;
    }

    event SaleFeesProcessed(uint256 saleId, SaleFees saleFees);
    event PaymentProcessed(address indexed from, address indexed to, uint256 amount);
    event ServiceFeePaid(bytes32 operation, address indexed wallet, uint256 amount);
    event RewardDistributed(address indexed referrer, address indexed referral, uint256 amount);
    event PurchaseFeesSplit(bool fiat, uint directSaleId, uint256 sellFees, uint256 buyFees);
    event FiatFeePercentageUpdated(uint96 oldPercentage, uint96 newPercentage);

    uint96 private _buyFeePercentage;
    uint96 private _sellFeePercentage;
    uint96 private _fiatFeePercentage;
    uint256 private constant THOUSANDTH_UNIT = 1000;
    mapping(uint256 => uint256) private _discounts;
    mapping(bytes32 => uint256) private _serviceFees;
    uint256 private _treasuryPercentage;
    uint256 private _brandPercentage;
    uint256 private _stakingPercentage;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _roles) public initializer {
        __Pausable_init();
        __UUPSUpgradeable_init();
        __Modifiers_init(_roles);
        _fiatFeePercentage = 100; // Default 1%
    }

    function calculateServiceFee(
        bytes32 operation
    ) internal view returns (ServiceFee memory) {
        uint256 baseFee = _serviceFees[operation];
        return ServiceFee({
            operation: operation,
            serviceFees: baseFee,
            fiatFees: 0 // Fiat fees will be calculated on total fees
        });
    }

    function calculateFiatFee(uint256 amount) internal view returns (uint256) {
        return (amount * _fiatFeePercentage) / THOUSANDTH_UNIT;
    }

    function splitServiceFee(
        bytes32 operation,
        address wallet,
        address erc20
    ) external override whenNotPaused onlyDelegatedRole onlyValidPayment(erc20) {
        bool isFiat = erc20 == address(0);
        ServiceFee memory serviceFee = calculateServiceFee(operation);
        uint256 totalFee = serviceFee.serviceFees;
        
        if (isFiat) {
            uint256 fiatFee = calculateFiatFee(serviceFee.serviceFees);
            totalFee += fiatFee;
        }

        address from = isFiat ? roles.getRoleAddress(FIAT) : wallet;
        address service = roles.getRoleAddress(SERVICE);

        if (!IERC20(erc20).transferFrom(
            from,
            service,
            totalFee
        )) revert TransferFailed();

        emit ServiceFeePaid(operation, wallet, totalFee);
    }

    function splitSaleFees(
        address erc20,
        uint directSaleId,
        address seller,
        uint price,
        address buyer,
        address brand
    ) external override whenNotPaused onlyDelegatedRole onlyValidPayment(erc20) {
        bool isFiat = erc20 == address(0);
        
        uint buyerMembership = IMemberships(roles.getRoleAddress(MEMBERSHIPS))
            .getMembership(buyer);
        uint sellerMembership = IMemberships(roles.getRoleAddress(MEMBERSHIPS))
            .getMembership(seller);

        uint256 buyFee =((price * _buyFeePercentage) - (price * buyerMembership)) / THOUSANDTH_UNIT;
        uint256 sellFee = (price * _sellFeePercentage) -
            (price * sellerMembership) /
            THOUSANDTH_UNIT;

        ServiceFee memory serviceFee = calculateServiceFee(BUY);
        
        // Calculate fiat fee on total of buyFee + serviceFee if payment is in fiat
        if (isFiat) {
            uint256 fiatFee = calculateFiatFee(buyFee + serviceFee.serviceFees);
            buyFee += fiatFee;
        }
            
        uint256 totalFees = buyFee + sellFee;

        uint256 brandFees = (totalFees * _brandPercentage) / 100;
        uint256 treasuryFees = (totalFees * _treasuryPercentage) / 100;
        uint256 stakingFees = (totalFees * _stakingPercentage) / 100;

        SaleFees memory fees = SaleFees({
            buyFee: buyFee,
            sellFee: sellFee,
            treasuryFee: treasuryFees,
            brandFee: brandFees,
            stakingFee: stakingFees,
            serviceFee: serviceFee
        });

        address from = isFiat ? roles.getRoleAddress(FIAT) : buyer;
        address treasury = roles.getRoleAddress(TREASURY);
        address service = roles.getRoleAddress(SERVICE);
        address staking = roles.getRoleAddress(STAKING);

        uint256 earning = price - totalFees;

        if (
            !IERC20(erc20).transferFrom(from, seller, earning) ||
            !IERC20(erc20).transferFrom(from, treasury, treasuryFees) ||
            !IERC20(erc20).transferFrom(from, brand, brandFees) ||
            !IERC20(erc20).transferFrom(from, staking, stakingFees) ||
            !IERC20(erc20).transferFrom(from, service, serviceFee.serviceFees)
        ) revert TransferFailed();

        emit SaleFeesProcessed(directSaleId, fees);
        emit PurchaseFeesSplit(isFiat, directSaleId, sellFee, buyFee);
    }

    function distributeRewards(
        address referrer,
        address referral,
        uint256 amount,
        bool shouldPayReferrer
    ) external override onlyDelegatedRole whenNotPaused {
        if (referrer == address(0) || amount == 0) return;
        
        address swapTreasury = roles.getRoleAddress(OWNER);
        
        if (shouldPayReferrer) {
            IERC20(roles.getRoleAddress(CRUTOKEN)).transferFrom(
                swapTreasury,
                referrer,
                amount
            );
        }

        if (referral != address(0)) {
            IERC20(roles.getRoleAddress(CRUTOKEN)).transferFrom(
                swapTreasury,
                referral,
                amount
            );
        }

        emit RewardDistributed(referrer, referral, amount);
    }

    function convert(
        address account,
        address erc20,
        uint256 amount
    ) external override onlyDelegatedRole onlyValidPayment(erc20) {
        if (amount == 0) revert InsufficientPayment(1, 0);

        uint256 tokenAmount = (amount * 10 ** 18) * 10;
        address swapTreasury = roles.getRoleAddress(SWAP);

        if (!IERC20(erc20).transferFrom(account, swapTreasury, amount)) {
            revert PaymentFailed(erc20, amount);
        }

        if (!IERC20(roles.getRoleAddress(CRUTOKEN)).transferFrom(
            swapTreasury,
            account,
            tokenAmount
        )) {
            revert PaymentFailed(roles.getRoleAddress(CRUTOKEN), tokenAmount);
        }

        emit PaymentProcessed(account, swapTreasury, amount);
    }

    function setFeePercentages(uint96 buyFee, uint96 sellFee) external onlyRole(OWNER) {
        _buyFeePercentage = buyFee;
        _sellFeePercentage = sellFee;
    }

    function setFiatFeePercentage(uint96 newPercentage) external onlyRole(OWNER) {
        uint96 oldPercentage = _fiatFeePercentage;
        _fiatFeePercentage = newPercentage;
        emit FiatFeePercentageUpdated(oldPercentage, newPercentage);
    }

    function setDistributionPercentages(
        uint256 treasury,
        uint256 brand,
        uint256 staking
    ) external onlyRole(OWNER) {
        require(treasury + brand + staking == 100, "Percentages must sum to 100");
        _treasuryPercentage = treasury;
        _brandPercentage = brand;
        _stakingPercentage = staking;
    }

    function setServiceFee(bytes32 operation, uint256 fee) external onlyRole(OWNER) {
        _serviceFees[operation] = fee;
    }

    function pause() external onlyRole(PAUSER) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER) {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER) {}
}