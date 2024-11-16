// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "./interfaces/IReferrals.sol";
import "./interfaces/ISales.sol";
import "./interfaces/IRoles.sol";
import "./abstracts/Modifiers.sol";
import "./interfaces/IPayments.sol";
import "./interfaces/IWrappers.sol";
import "./interfaces/IWhitelist.sol";
import "./interfaces/IMemberships.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract Sales is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    Modifiers
{
    using EnumerableSet for EnumerableSet.UintSet;

    struct SaleCollection {
        mapping(uint256 => Sale) sales;
        EnumerableSet.UintSet saleIds;
    }

    // Mappings
    mapping(uint256 => uint256) private _delays;
    mapping(uint256 => uint256) private _durations;
    mapping(uint256 => uint256) private _schedules;
    mapping(uint256 => uint256) private _priorities;
    mapping(bytes32 => SaleCollection) private _sales;
    mapping(uint256 => Sale) private _salesData;

    uint256 private _scheduleDay;
    uint256 private _delayId;
    uint256 private _currentSaleId = 1;

    function initialize(address _roles) public initializer {
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        __Modifiers_init(_roles);

        _scheduleDay = 6;
        _delays[1] = 1 minutes;
        _delays[0] = 2 minutes;
        _durations[0] = 5 minutes;
    }

    // ... altre funzioni invariate ...

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
        Date[] memory dates = new Date[](length);
        uint256[] memory salesIds = new uint256[](length);

        for (uint256 i; i < length; i++) {
            uint256 saleId = _currentSaleId++;
            SaleInput memory inputs = salesInputs[i];

            IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));
            bytes32 collection = wrappers.getData(inputs.wrapperId).sku;

            if (
                IERC721(roles.getRoleAddress(WRAPPERS)).ownerOf(
                    inputs.wrapperId
                ) != seller
            ) {
                revert NotOwner(
                    seller,
                    IERC721(roles.getRoleAddress(WRAPPERS)).ownerOf(
                        inputs.wrapperId
                    )
                );
            }

            uint256 start = block.timestamp +
                _delays[_delayId == 0 ? _delayId++ : _delayId--];
            uint256 duration = _durations[0];
            uint256 end = start + duration;

            Sale memory newSale = Sale({
                price: inputs.price,
                seller: seller,
                end: uint40(end),
                duration: uint40(duration),
                start: uint40(start),
                id: saleId
            });

            _salesData[saleId] = newSale;
            _sales[collection].sales[saleId] = newSale;
            _sales[collection].saleIds.add(saleId);

            IPayments(roles.getRoleAddress(PAYMENTS)).splitServiceFee(
                LIST,
                seller,
                erc20
            );

            wrappers.marketplaceTransfer(
                seller,
                address(this),
                inputs.wrapperId
            );

            salesIds[i] = saleId;
            dates[i] = Date({expireListDate: end, expireUpcomeDate: start});
        }

        emit List(salesIds, dates);
    }

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
        IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));

        for (uint256 i; i < salesIds.length; i++) {
            uint256 saleId = salesIds[i];
            Wrapper memory wrapper = wrappers.getData(saleId);
            Sale storage sale = _sales[wrapper.sku].sales[saleId];

            require(block.timestamp <= sale.end, "Sale expired");
            require(
                IWhitelist(roles.getRoleAddress(WHITELIST)).isWhitelisted(
                    sale.seller
                ),
                "Not Whitelisted"
            );
            require(
                block.timestamp -
                    _priorities[
                        IMemberships(roles.getRoleAddress(MEMBERSHIPS))
                            .getMembership(buyer)
                    ] >
                    sale.start,
                "Sale not started yet"
            );

            IPayments(roles.getRoleAddress(PAYMENTS)).splitSaleFees(
                erc20,
                saleId,
                sale.seller,
                sale.price,
                buyer,
                IBrands(roles.getRoleAddress(BRANDS))
                    .getBrand(wrapper.brandId)
                    .owner
            );

            // Aggiornato per passare anche shouldPayReferrer come true
            IReferrals(roles.getRoleAddress(REFERRALS)).useReferral(
                buyer,
                sale.price
            );

            wrappers.marketplaceTransfer(address(this), buyer, saleId);

            delete _sales[wrapper.sku].sales[saleId];
            _sales[wrapper.sku].saleIds.remove(saleId);
        }

        emit Buy(salesIds);
    }

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
        bytes32 collection;
        IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));

        for (uint256 i = 0; i < salesIds.length; i++) {
            uint256 saleId = salesIds[i];
            collection = wrappers.getData(saleId).sku;
            Sale storage sale = _sales[collection].sales[saleId];

            if (sale.seller != seller) {
                revert NotOwner(seller, sale.seller);
            }

            IPayments(roles.getRoleAddress(PAYMENTS)).splitServiceFee(
                WITHDRAW,
                seller,
                erc20
            );

            wrappers.marketplaceTransfer(address(this), seller, saleId);

            delete _sales[collection].sales[salesIds[i]];
            _sales[collection].saleIds.remove(salesIds[i]);
        }

        emit Withdraw(salesIds);
    }

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
        uint length = salesIds.length;
        Date[] memory dates = new Date[](length);
        bytes32 collection;
        IWrappers wrappers = IWrappers(roles.getRoleAddress(WRAPPERS));

        for (uint256 i = 0; i < length; i++) {
            uint256 saleId = salesIds[i];
            collection = wrappers.getData(saleId).sku;
            Sale storage sale = _sales[collection].sales[saleId];

            if (sale.seller != seller) {
                revert NotOwner(seller, sale.seller);
            }

            IPayments(roles.getRoleAddress(PAYMENTS)).splitServiceFee(
                RENEW,
                seller,
                erc20
            );

            uint end = block.timestamp + sale.duration;
            sale.end = uint40(end);
            dates[i] = Date({
                expireListDate: end,
                expireUpcomeDate: block.timestamp
            });
        }

        emit Renew(salesIds, dates);
    }

    function setSchedules(
        uint[] calldata scheduleIds,
        uint256[] calldata timestamps
    ) external onlyRole(OWNER) {
        require(scheduleIds.length == timestamps.length, "Mismatched lengths");
        for (uint256 i = 0; i < scheduleIds.length; i++) {
            _schedules[scheduleIds[i]] = timestamps[i];
            emit ScheduleSet(scheduleIds[i], timestamps[i]);
        }
    }

    function setDurations(
        uint[] calldata durationIds,
        uint256[] calldata durations
    ) external onlyRole(OWNER) {
        require(durationIds.length == durations.length, "Mismatched lengths");
        for (uint256 i = 0; i < durationIds.length; i++) {
            _durations[durationIds[i]] = durations[i];
            emit DurationSet(durationIds[i], durations[i]);
        }
    }

    function setDelays(
        uint[] calldata scheduleIds,
        uint256[] calldata delays
    ) external onlyRole(OWNER) {
        require(scheduleIds.length == delays.length, "Mismatched lengths");
        for (uint256 i = 0; i < scheduleIds.length; i++) {
            _delays[scheduleIds[i]] = delays[i];
            emit DelaySet(scheduleIds[i], delays[i]);
        }
    }

    function setScheduleDay(uint newScheduleDay) external onlyRole(OWNER) {
        require(newScheduleDay < 7, "Invalid schedule day");
        _scheduleDay = newScheduleDay;
    }

    function getScheduleDay() external view returns (uint) {
        return _scheduleDay;
    }

    function getDelay(uint scheduleId) external view returns (uint256) {
        return _delays[scheduleId];
    }

    function getDuration(uint durationId) external view returns (uint256) {
        return _durations[durationId];
    }

    function getSchedule(uint scheduleId) external view returns (uint256) {
        return _schedules[scheduleId];
    }

    function pause() external onlyRole(PAUSER) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER) {
        _unpause();
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER) {}
}
