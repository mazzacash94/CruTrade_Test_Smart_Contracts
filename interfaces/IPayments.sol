// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

error TransferFailed();
error InsufficientPayment(uint256 required, uint256 provided);
error InvalidPaymentToken(address token);
error PaymentFailed(address token, uint256 amount);
// IPayments.sol
interface IPayments {
    function splitSaleFees(
        address erc20,
        uint directSaleId,
        address seller,
        uint price,
        address buyer,
        address brand
    ) external;

    function splitServiceFee(
        bytes32 operation,
        address wallet,
        address erc20
    ) external;

    function convert(
        address account,
        address erc20,
        uint256 amount
    ) external;

    function distributeRewards(
        address referrer,
        address referral,
        uint256 amount,
        bool shouldPayReferrer
    ) external;
}
