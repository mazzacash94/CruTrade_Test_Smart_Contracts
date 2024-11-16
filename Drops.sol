// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./abstracts/Modifiers.sol";

/// @title Drops
/// @notice Manages NFT pools for airdrops with upgradeable functionality
/// @dev Implements UUPS upgradeable pattern with role-based access control
contract Drops is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    Modifiers
{
    /// @notice Structure defining an NFT pool
    /// @param active Whether the pool is currently active
    /// @param owner Address of the pool owner
    /// @param token Address of the NFT contract
    /// @param counter Current number of tokens distributed
    /// @param feature Feature identifier for the pool
    /// @param tokenIds Array of token IDs in the pool
    struct Pool {
        bool active;
        address owner;
        address token;
        uint256 counter;
        bytes32 feature;
        uint256[] tokenIds;
    }

    /// @notice Total number of pools created
    uint256 public poolCount;

    /// @notice Mapping from pool ID to Pool struct
    mapping(uint256 => Pool) public _pools;

    /// @notice Event emitted when tokens are recovered from a pool
    /// @param poolId ID of the pool from which tokens were recovered
    /// @param owner Address of the pool owner receiving the tokens
    /// @param tokenIds Array of recovered token IDs
    event PoolRecovered(
        uint256 indexed poolId,
        address indexed owner,
        uint256[] tokenIds
    );

    /// @notice Emitted when a new pool is created
    event PoolCreated(
        uint256 indexed poolId,
        address indexed owner,
        address indexed token,
        bytes32 feature
    );

    /// @notice Emitted when a token is transferred to a to
    event TokenTransferred(
        uint256 indexed poolId,
        address indexed to,
        uint256 tokenId
    );

    /// @notice Emitted when tokens are added to a pool
    event TokensAdded(uint256 indexed poolId, uint256[] tokenIds);

    /// @notice Emitted when a pool's owner is updated
    event PoolUpdated(uint256 indexed poolId, address owner);

    /// @notice Emitted when tokens are recovered from a pool
    event TokensRecovered(uint256 indexed poolId, uint256[] tokenIds);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _roles Address of the roles contract
    function initialize(address _roles) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __Modifiers_init(_roles);
    }

    /// @notice Updates the roles contract address
    /// @param _roles New roles contract address
    function setRoles(address _roles) external onlyRole(OWNER) {
        roles = IRoles(_roles);
    }

    /// @notice Creates a new pool
    /// @param owner Address that will own the pool
    /// @param token Address of the NFT contract
    /// @param feature Feature identifier for the pool
    function createPool(
        address owner,
        address token,
        bytes32 feature
    ) external onlyRole(OWNER) {
        uint poolId = poolCount;
        unchecked {
            ++poolCount;
        }
        _pools[poolId] = Pool({
            active: true,
            owner: owner,
            token: token,
            feature: feature,
            counter: 0,
            tokenIds: new uint256[](0)
        });

        emit PoolCreated(poolId, owner, token, feature);
    }

    /// @notice Fills a pool with tokens
    /// @param poolId ID of the pool to fill
    /// @param tokenIds Array of token IDs to add to the pool
    function fillPool(
        uint256 poolId,
        uint256[] calldata tokenIds
    ) public onlyRole(OWNER) {
        Pool storage pool = _pools[poolId];
        require(pool.active, "Pool not active");
        IERC721 token = IERC721(pool.token);
        for (uint256 i = 0; i < tokenIds.length; ) {
            token.transferFrom(pool.owner, address(this), tokenIds[i]);
            pool.tokenIds.push(tokenIds[i]);
            unchecked {
                ++i;
            }
        }

        emit TokensAdded(poolId, tokenIds);
    }

    /// @notice Emitted when tokens are airdropped to a to
    /// @param poolId ID of the pool from which tokens were airdropped
    /// @param to Address that received the tokens
    /// @param tokenIds Array of transferred token IDs
    event Aidrop(
        uint256 indexed poolId,
        address indexed to,
        uint256[] tokenIds
    );

    /// @notice Airdrops multiple tokens to a to
    /// @param amount Number of tokens to airdrop
    /// @param poolId ID of the pool to airdrop from
    /// @param to Address to receive the tokens
    function airdrop(
        address to,
        uint256 amount,
        uint256 poolId
    ) external onlyRole(OWNER) whenNotPaused {
        require(to != address(0), "Invalid to");

        Pool storage pool = _pools[poolId];
        uint256 counter = pool.counter;
        require(pool.active, "Pool not active");
        require(counter + amount <= pool.tokenIds.length, "Not enough tokens");

        // Pre-allocate array for tracking transferred tokenIds
        uint256[] memory tokens = new uint256[](amount);

        // Cache token contract to save gas
        IERC721 token = IERC721(pool.token);

        // Transfer tokens and track IDs

        for (uint256 i = 0; i < amount; ) {
            uint256 tokenId = pool.tokenIds[counter];
            token.transferFrom(address(this), to, tokenId);
            tokens[i] = tokenId;
            unchecked {
                ++i;
                ++counter;
            }
        }

        // Update pool counter
        pool.counter = counter;

        // Emit single event with all transferred tokens
        emit Aidrop(poolId, to, tokens);
    }

    /// @notice Updates the owner of a pool
    /// @param poolId ID of the pool to update
    /// @param owner New owner address
    function updatePoolOwner(
        uint256 poolId,
        address owner
    ) external onlyRole(OWNER) {
        Pool storage pool = _pools[poolId];
        require(pool.active, "Pool not active");

        pool.owner = owner;

        emit PoolUpdated(poolId, owner);
    }

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

    /// @notice Gets the number of remaining tokens in a pool
    /// @param poolId ID of the pool to query
    /// @return Number of remaining tokens
    function getRemainingTokens(
        uint256 poolId
    ) external view returns (uint256) {
        Pool memory pool = _pools[poolId];
        return pool.tokenIds.length - pool.counter;
    }

    /// @notice Toggles the pause state of the contract
    function togglePause() external onlyRole(PAUSER) {
        paused() ? _unpause() : _pause();
    }

    /// @notice Deactivates a pool
    /// @param poolId ID of the pool to deactivate
    function deactivatePool(uint256 poolId) external onlyRole(OWNER) {
        _pools[poolId].active = false;
    }

    /// @notice Transfers remaining tokens back to the pool owner
    /// @param poolId ID of the pool to transfer tokens from
    /// @return tokenIds Array of transferred token IDs
    function recoverPool(
        uint256 poolId
    ) external onlyRole(OWNER) returns (uint256[] memory tokenIds) {
        Pool storage pool = _pools[poolId];
        require(pool.active, "Pool not active");

        uint256 counter = pool.counter;
        uint256 length = pool.tokenIds.length;

        uint256 remaining = length - counter;
        require(remaining > 0, "No tokens to transfer");

        // Pre-allocate array for transferred token IDs
        tokenIds = new uint256[](remaining);

        // Cache pool owner to save gas
        address owner = pool.owner;
        // Cache token contract to save gas
        IERC721 token = IERC721(pool.token);

        // Transfer tokens and track IDs

        for (uint256 i = 0; i < remaining; ) {
            unchecked {
                uint256 tokenId = pool.tokenIds[counter + i];
                token.transferFrom(address(this), owner, tokenId);
                tokenIds[i] = tokenId;
                ++i;
            }
        }

        // Update counter
        pool.counter = length;

        // Emit event with all recovered token IDs
        emit PoolRecovered(poolId, owner, tokenIds);
    }

    /// @notice Authorizes an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER) {}
}
