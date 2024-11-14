// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

error Locked();
error NotListedYet();
error NotAllowed(bytes32 role, address account);
error TransferFailed();
error Finished();
error NotRenewable();
error NotWithdrawable();
error AlreadyBroken();
error InvalidSignature(address signer, address recoveredSigner);
error NotOwner(address expectedOwner, address actualOwner);
error NotWhitelisted(address wallet);
error InvalidBrand(uint256 brandId);
error PaymentNotAllowed(address payment);
error NotAllowedDelegate(address caller);
