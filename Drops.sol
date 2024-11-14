// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/utils/Pausable.sol';

/**
 * @title NFT Drops Contract
 * @dev Manages sequential NFT distributions through time-based pools
 */
contract Drops is Ownable, Pausable {
  struct Pool {
    uint256 startTime;
    uint256 endTime;
    uint256 currentIndex;
    uint256 maxTokens;
    bool active;
    uint256[] tokenIds;
  }

  IERC721 public immutable nftContract;
  mapping(uint256 => Pool) public pools;
  uint256 public poolCount;

  event PoolCreated(
    uint256 indexed poolId,
    uint256 startTime,
    uint256 endTime,
    uint256 maxTokens
  );

  event TokenTransferred(
    uint256 indexed poolId,
    address indexed recipient,
    uint256 tokenId
  );

  event TokensAdded(uint256 indexed poolId, uint256[] tokenIds);

  event PoolUpdated(uint256 indexed poolId, uint256 startTime, uint256 endTime);

  /**
   * @dev Initialize the drops contract with the NFT contract address
   * @param _nftContract Address of the NFT contract
   */
  constructor(address _nftContract) Ownable(msg.sender) {
    require(_nftContract != address(0), 'Invalid NFT contract');
    nftContract = IERC721(_nftContract);
  }

  /**
   * @dev Creates a new distribution pool
   * @param endTime Pool end timestamp
   * @param maxTokens Maximum tokens allowed in pool
   * @param tokenIds Initial token IDs to add
   * @return poolId Unique identifier for the created pool
   */
  function createPool(
    uint256 endTime,
    uint256 maxTokens,
    uint256[] calldata tokenIds
  ) external onlyOwner returns (uint256 poolId) {
    require(maxTokens > 0, 'Max tokens must be positive');

    uint timestamp = block.timestamp;

    poolId = poolCount++;
    pools[poolId] = Pool({
      startTime: timestamp,
      endTime: endTime,
      currentIndex: 0,
      maxTokens: maxTokens,
      active: true,
      tokenIds: new uint256[](0)
    });

    if (tokenIds.length > 0) {
      addTokensToPool(poolId, tokenIds);
    }

    emit PoolCreated(poolId, timestamp, endTime, maxTokens);
  }

  /**
   * @dev Adds tokens to an existing pool
   * @param poolId Pool identifier
   * @param tokenIds Array of token IDs to add
   */
  function addTokensToPool(
    uint256 poolId,
    uint256[] calldata tokenIds
  ) public onlyOwner {
    Pool storage pool = pools[poolId];
    require(pool.active, 'Pool not active');
    require(
      pool.tokenIds.length + tokenIds.length <= pool.maxTokens,
      'Exceeds pool limit'
    );

    for (uint256 i = 0; i < tokenIds.length; i++) {
      nftContract.transferFrom(msg.sender, address(this), tokenIds[i]);
      pool.tokenIds.push(tokenIds[i]);
    }

    emit TokensAdded(poolId, tokenIds);
  }

  /**
   * @dev Transfers the next available token from the pool to recipient
   * @param poolId Pool identifier
   * @param recipient Address to receive the token
   */
  function airdrop(
    uint256 poolId,
    address recipient
  ) external onlyOwner whenNotPaused {
    require(recipient != address(0), 'Invalid recipient');

    Pool storage pool = pools[poolId];
    require(pool.active, 'Pool not active');
    require(block.timestamp >= pool.startTime, 'Pool not started');
    require(block.timestamp <= pool.endTime, 'Pool ended');
    require(pool.currentIndex < pool.tokenIds.length, 'No tokens available');

    uint256 tokenId = pool.tokenIds[pool.currentIndex];
    pool.currentIndex++;

    nftContract.transferFrom(address(this), recipient, tokenId);

    emit TokenTransferred(poolId, recipient, tokenId);
  }

  /**
   * @dev Updates pool timing parameters
   * @param poolId Pool identifier
   * @param newStartTime New start timestamp
   * @param newEndTime New end timestamp
   */
  function updatePoolTimes(
    uint256 poolId,
    uint256 newStartTime,
    uint256 newEndTime
  ) external onlyOwner {
    require(newStartTime > block.timestamp, 'Start time must be future');
    require(newEndTime > newStartTime, 'End time must be after start');

    Pool storage pool = pools[poolId];
    require(pool.active, 'Pool not active');

    pool.startTime = newStartTime;
    pool.endTime = newEndTime;

    emit PoolUpdated(poolId, newStartTime, newEndTime);
  }

  /**
   * @dev Returns remaining token count in pool
   * @param poolId Pool identifier
   * @return count Number of tokens remaining
   */
  function getRemainingTokens(uint256 poolId) external view returns (uint256) {
    Pool storage pool = pools[poolId];
    return pool.tokenIds.length - pool.currentIndex;
  }

  /**
   * @dev Toggles pause state
   */
  function togglePause() external onlyOwner {
    paused() ? _unpause() : _pause();
  }

  /**
   * @dev Deactivates a pool
   * @param poolId Pool identifier
   */
  function deactivatePool(uint256 poolId) external onlyOwner {
    pools[poolId].active = false;
  }
}
