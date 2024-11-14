// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/access/IAccessControl.sol';

    /* EVENTS */

    event PurchaseFeesSplit(
        bool indexed fiat,
        uint256 indexed directSaleId,
        uint256 sellFees,
        uint256 buyFees
    );

    event FeaturedPayment(
        address indexed from,
        uint256 indexed operation,
        uint256 indexed directSaleId,
        uint256 amount
    );

    event FeeConfigUpdated(
        uint32 buyFee,
        uint32 sellFee,
        uint32 treasuryFee,
        uint32 brandFee,
        uint32 stakingFee
    );

    /* ERRORS */

    error ExcessiveFees(uint256 total, uint256 max);
    error InvalidFeeConfiguration();
    error TransferBatch();
    error ZeroAmount();

/**
 * @title IRoles
 * @dev Interface for managing roles and permissions in the Crutrade ecosystem.
 * Extends OpenZeppelin's IAccessControl with additional custom functionality.
 */
interface IRoles is IAccessControl {
    /**
     * @dev Checks if a contract has been delegated a role.
     * @param _contract Address of the contract to check.
     * @return True if the contract has a delegate role, false otherwise.
     */
    function hasDelegateRole(address _contract) external view returns (bool);

    /**
     * @dev Checks if a contract is authorized for payment operations.
     * @param _contract Address of the contract to check.
     * @return True if the contract has a payment role, false otherwise.
     */
    function hasPaymentRole(address _contract) external view returns (bool);

    /**
     * @dev Retrieves the address associated with a specific role.
     * @param role The role identifier.
     * @return The address assigned to the specified role.
     */
    function getRoleAddress(bytes32 role) external view returns (address);
}

/**
 * @dev Emitted when the Roles contract address is set or updated.
 * @param roles The address of the new Roles contract.
 */
event RolesSet(address indexed roles);

/**
 * @dev Emitted when a payment role is granted to a contract.
 * @param payment Address of the contract granted the payment role.
 */
event PaymentRoleGranted(address indexed payment);

/**
 * @dev Emitted when a payment role is revoked from a contract.
 * @param payment Address of the contract from which the payment role is revoked.
 */
event PaymentRoleRevoked(address indexed payment);

/**
 * @dev Emitted when a delegate role is granted to a contract.
 * @param _contract Address of the contract granted the delegate role.
 */
event DelegateRoleGranted(address indexed _contract);

/**
 * @dev Emitted when a delegate role is revoked from a contract.
 * @param _contract Address of the contract from which the delegate role is revoked.
 */
event DelegateRoleRevoked(address indexed _contract);