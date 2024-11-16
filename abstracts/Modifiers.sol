// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import "../abstracts/RolesVariables.sol";
import "../interfaces/IRoles.sol";
import "../interfaces/IBrands.sol";
import "../interfaces/IWhitelist.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

error InvalidBrand(uint256 brandId);
error NotWhitelisted(address wallet);
error PaymentNotAllowed(address payment);
error NotAllowedDelegate(address account);
error NotAllowed(bytes32 role, address account);
error NotOwner(address claimer, address actualOwner);
error InvalidSignature(address expected, address actual);

/**
 * @title Modifiers
 * @dev Abstract contract providing common modifiers and initialization for role-based access control.
 */
abstract contract Modifiers is Initializable, RolesVariables {
    IRoles internal roles;

    /**
     * @dev Initializes the Modifiers contract.
     * @param _roles Address of the Roles contract.
     */
    function __Modifiers_init(address _roles) internal onlyInitializing {
        roles = IRoles(_roles);
    }

    /**
     * @dev Modifier to verify the signature of a message.
     * @param wallet Address of the signer.
     * @param hash Hash of the message.
     * @param signature Signature to verify.
     */
    modifier checkSignature(
        address wallet,
        bytes32 hash,
        bytes calldata signature
    ) {
        address recoveredSigner = ECDSA.recover(
            MessageHashUtils.toEthSignedMessageHash(hash),
            signature
        );
        if (recoveredSigner != wallet)
            revert InvalidSignature(wallet, recoveredSigner);
        _;
    }

    /**
     * @dev Modifier to restrict access to accounts with a specific role.
     * @param role The role required to access the function.
     */
    modifier onlyRole(bytes32 role) {
        if (!roles.hasRole(role, msg.sender))
            revert NotAllowed(role, msg.sender);
        _;
    }

    /**
     * @dev Modifier to restrict access to delegated roles.
     */
    modifier onlyDelegatedRole() {
        if (!roles.hasDelegateRole(msg.sender))
            revert NotAllowedDelegate(msg.sender);
        _;
    }

    /**
     * @dev Modifier to restrict access to whitelisted addresses.
     * @param wallet Address to check for whitelist status.
     */
    modifier onlyWhitelisted(address wallet) {
        if (!IWhitelist(roles.getRoleAddress(WHITELIST)).isWhitelisted(wallet))
            revert NotWhitelisted(wallet);
        _;
    }

    /**
     * @dev Modifier to check if a brand ID is valid.
     * @param brandId The ID of the brand to check.
     */
    modifier onlyAllowedBrand(uint256 brandId) {
        if (!IBrands(roles.getRoleAddress(BRANDS)).isValidBrand(brandId))
            revert InvalidBrand(brandId);
        _;
    }

    /**
     * @dev Modifier to check if a payment method is allowed.
     * @param payment Address of the payment method.
     */
    modifier onlyValidPayment(address payment) {
        if (!roles.hasPaymentRole(payment)) revert PaymentNotAllowed(payment);
        _;
    }

    /**
     * @dev Modifier to restrict access to the owner of a specific token.
     * @param wallet Address claiming to be the owner.
     * @param tokenId ID of the token.
     */
    modifier onlyTokenOwner(address wallet, uint256 tokenId) {
        address actualOwner = IERC721(roles.getRoleAddress(WRAPPERS)).ownerOf(
            tokenId
        );
        if (actualOwner != wallet) revert NotOwner(wallet, actualOwner);
        _;
    }
}
