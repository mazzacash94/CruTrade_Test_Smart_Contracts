// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IMemberships {
    function getMembership(address account)
        external
        view
        returns (uint256);
}
