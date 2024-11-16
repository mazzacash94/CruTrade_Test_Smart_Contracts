// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// Events
event Add(address[] wallets);
event Remove(address[] wallets);

// Errors
error AddressAlreadyWhitelisted(address wallet);
error AddressNotWhitelisted(address wallet);
error InvalidWhitelistOperation();

interface IWhitelist {
    function isWhitelisted(address wallet) external view returns (bool);
}