// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

event Add(address[] wallets);
event Remove(address[] wallets);

interface IWhitelist {
    function isWhitelisted(address wallet) external view returns (bool);
}
