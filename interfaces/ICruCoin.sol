// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICruCoin is IERC20 {
    function stakingTransfer(address from, address to, uint256 amount) external;
}