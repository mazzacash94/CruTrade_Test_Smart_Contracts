// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Structs
struct FeatureInput {
    bytes data;  
    uint featureId;
}

struct Date {
    uint256 expireListDate;
    uint256 expireUpcomeDate;
}

struct Sale {
    uint256 id;
    uint256 end;
    uint256 price;
    uint256 start;
    address seller;
    uint256 duration;  
}

struct SaleInput {
    uint256 price;
    uint256 wrapperId;
    uint256 durationId;
    FeatureInput[] features;
}

// Events
event List(uint[] salesIds, Date[] dates);
event Buy(uint[] salesIds);
event Renew(uint[] salesIds, Date[] dates);
event Withdraw(uint[] salesIds);  
event DelaySet(uint indexed scheduleId, uint256 delay);
event ScheduleSet(uint indexed scheduleId, uint256 timestamp);
event DurationSet(uint indexed durationId, uint256 duration);

// Errors 
error SaleNotFound(uint256 saleId);
error InvalidSalePrice(uint256 price);
error SaleExpired(uint256 endTime);
error InvalidSaleDuration(uint256 duration);

interface ISales {
    function getSale(uint saleId) external view returns (Sale memory);
}