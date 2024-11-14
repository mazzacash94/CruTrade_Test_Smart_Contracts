// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './abstracts/Modifiers.sol';
import "./interfaces/IRoles.sol";
import "./interfaces/IMemberships.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @dev Emitted when a member joins a round.
 * @param members Addresses of the members.
 * @param membershipId Membership ID assigned to the member.
 */
event Joined(address[] members, uint256 indexed membershipId);

/**
 * @title Memberships
 * @notice Manages partner memberships in the Crutrade ecosystem.
 */
contract Memberships is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    IMemberships,
    Modifiers
{
    /* INITIALIZATION */

    /**
     * @dev Disables initializers for this contract.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with the roles contract address.
     * @param roles Address of the roles contract.
     */
    function initialize(address roles) public initializer {
        __Pausable_init();
        __UUPSUpgradeable_init();
        __Modifiers_init(roles);
    }

    /* VARIABLES */

    /* MAPPINGS */


    mapping(address => uint) private _memberships;

    /* SETTERS */

    /**
     * @dev Pauses the contract.
     * Can only be called by an account with the PAUSER role.
     */
    function pause() external onlyRole(PAUSER) {
        _pause();
    }

    /**
     * @dev Unpauses the contract.
     * Can only be called by an account with the PAUSER role.
     */
    function unpause() external onlyRole(PAUSER) {
        _unpause();
    }

    /**
     * @dev Updates the roles contract address.
     * @param _roles Address of the new roles contract.
     */
    function setRoles(address _roles) external onlyRole(OWNER) {
        roles = IRoles(_roles);
        emit RolesSet(_roles);
    }

    /* PUBLIC FUNCTIONS */

    /**
     * @dev Sets the membership ID for multiple members for the current snapshot.
     * @param members Array of member addresses.
     * @param id Membership ID to assign.
     */
    function setMemberships(address[] calldata members, uint id) external onlyRole(MEMBERSHIPPER) {
        uint length = members.length;
        for (uint i; i < length; i++) {
            _memberships[members[i]] = id;
        }
        emit Joined(members, id);
    }

    /* OVERRIDES */

    /**
     * @dev Retrieves the current membership ID for a given account.
     * @param account Address of the account.
     * @return Membership ID for the account.
     */
    function getMembership(address account)
        external
        view
        override
        returns (uint256)
    {
        return _memberships[account];
    }

    /**
     * @dev Authorizes the upgrade of the contract.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER) {}
}
