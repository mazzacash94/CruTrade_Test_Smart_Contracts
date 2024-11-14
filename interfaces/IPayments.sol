// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

interface IPayments {

    function splitSaleFees(
        address erc20,
        address seller,
        uint price,
        address buyer,
        address brand
    ) external payable         returns (
            uint256 serviceFee,
            uint256 buyFee,
            uint256 sellFee,
            uint256 treasuryFee,
            uint256 brandFee,
            uint256 stakingFee,
            uint256 fiatFee
        );

    function splitServiceFee(bytes32 operation, address wallet, address erc20) external payable returns(uint,uint);

    function featuredPayment(
        address seller,
        uint operation,
        address erc20,
        uint directSaleId,
        uint amount
    ) external payable;

    function swap(address account, address erc20, uint256 amount) external payable;

        function distributeRewards(address referrer, address referral, uint256 price) external;

}
