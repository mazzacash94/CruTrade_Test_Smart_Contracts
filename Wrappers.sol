// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './interfaces/IRoles.sol';
import './interfaces/IBrands.sol';
import './abstracts/Modifiers.sol';
import './interfaces/IWrappers.sol';
import './interfaces/IWhitelist.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/access/IAccessControl.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721PausableUpgradeable.sol';

/**
 * @title Wrappers
 * @dev Implements a wrapper system for NFTs with brand and category management
 * @notice This contract manages wrapped NFT collections with brand and category classifications
 * @custom:security-contact security@yourproject.com
 */
contract Wrappers is
  Initializable,
  UUPSUpgradeable,
  ERC721Upgradeable,
  IWrappers,
  ERC721PausableUpgradeable,
  Modifiers
{
  using EnumerableSet for EnumerableSet.UintSet;

  /**
   * @dev Struct representing a collection of wrappers for a specific brand and category
   * @notice Contains a mapping of wrapper IDs to Wrapper structs and a set of active wrapper IDs
   */
  struct Collection {
    mapping(uint256 => Wrapper) wrappers;
    EnumerableSet.UintSet wrapperIds;
  }

  /// @dev Counter for generating unique wrapper IDs
  uint256 private _wrapperIdCounter;

  /// @dev Nested mapping: brandId => category => Collection
  mapping(uint256 => mapping(bytes32 => Collection)) private _collections;

  /// @dev Custom error for zero address inputs
  error ZeroAddress();
  /// @dev Custom error for empty array inputs
  error EmptyInput();
  /// @dev Custom error for invalid token operations
  error InvalidToken();

  /**
   * @dev Constructor that disables initialization for the implementation contract
   */
  constructor() {
    _disableInitializers();
  }

  /**
   * @dev Initializes the contract with required parameters
   * @param _roles Address of the roles contract
   * @notice Sets up the ERC721 token with name and symbol, and mints initial tokens
   * @custom:requirement _roles must be a valid contract address
   */
  function initialize(address _roles) public initializer {
    if (_roles == address(0)) revert ZeroAddress();

    __ERC721Pausable_init();
    __UUPSUpgradeable_init();
    __ERC721_init('Crutrade Wrappers', 'CRUW');
    __Modifiers_init(_roles);

    uint dropWrapperId = 100_000;
    for (uint i; i < 10; ++i) {
      _mint(0xd6ef21b20D3Bb4012808695c96A60f6032e14FB6, dropWrapperId++);
    }
  }

  /**
   * @dev Pauses all token transfers and operations
   * @notice Can only be called by accounts with PAUSER role
   */
  function pause() external payable onlyRole(PAUSER) {
    _pause();
  }

  /**
   * @dev Unpauses all token transfers and operations
   * @notice Can only be called by accounts with PAUSER role
   */
  function unpause() external payable onlyRole(PAUSER) {
    _unpause();
  }

  /**
   * @dev Updates the roles contract address
   * @param _roles New roles contract address
   * @notice Can only be called by the contract owner
   * @custom:requirement _roles must be a valid contract address
   */
  function setRoles(address _roles) external payable onlyRole(OWNER) {
    if (_roles == address(0)) revert ZeroAddress();
    roles = IRoles(_roles);
    emit RolesSet(_roles);
  }

  /**
   * @dev Checks if a wrapper exists in a specific category
   * @param category Category identifier
   * @param wrapperId Wrapper token ID
   * @return bool True if wrapper exists in the category
   */
  function checkCollection(
    bytes32 category,
    uint256 wrapperId
  ) public view override returns (bool) {
    Wrapper storage wrapper = _collections[getData(wrapperId).brandId][category]
      .wrappers[wrapperId];
    return wrapper.brandId != 0;
  }

  /**
   * @dev Verifies if a brand-category combination has any wrappers
   * @param brandId Brand identifier
   * @param category Category identifier
   * @return bool True if the collection contains any wrappers
   */
  function isValidCollection(
    uint brandId,
    bytes32 category
  ) external view override returns (bool) {
    return _collections[brandId][category].wrapperIds.length() != 0;
  }

  /**
   * @dev Retrieves wrapper data for a given token ID
   * @param tokenId Token identifier
   * @return Wrapper struct containing wrapper details
   */
  function getData(
    uint256 tokenId
  ) public view override returns (Wrapper memory) {
    (uint256 brandId, bytes32 sku) = _getBrandIdAndSku(tokenId);
    return _collections[brandId][sku].wrappers[tokenId];
  }

  /**
   * @dev Gets the brand ID for a given token
   * @param tokenId Token identifier
   * @return uint256 Brand identifier
   */
  function getBrand(uint256 tokenId) public view override returns (uint256) {
    (uint256 brandId, ) = _getBrandIdAndSku(tokenId);
    return brandId;
  }

  /**
   * @dev Exports (burns) multiple wrappers from a whitelisted wallet
   * @param wallet Address of the wallet to export from
   * @param ids Array of token IDs to export
   * @notice Only callable by EXPORTER role when contract is not paused
   * @custom:requirement Wallet must be whitelisted
   */
  function exports(
    address wallet,
    uint[] calldata ids
  ) external whenNotPaused onlyRole(EXPORTER) onlyWhitelisted(wallet) {
    if (wallet == address(0)) revert ZeroAddress();
    if (ids.length == 0) revert EmptyInput();

    uint256 length = ids.length;
    for (uint256 i; i < length; ) {
      uint256 id = ids[i];
      (uint256 brandId, bytes32 sku) = _getBrandIdAndSku(id);
      Collection storage collection = _collections[brandId][sku];

      collection.wrapperIds.remove(id);
      delete collection.wrappers[id];
      _burn(id);

      unchecked {
        ++i;
      }
    }

    emit Export(wallet, ids);
  }

  /**
   * @dev Imports (mints) multiple wrappers to a whitelisted address
   * @param to Recipient address
   * @param brandId Brand identifier
   * @param wrappers Array of WrapperInput structs containing wrapper details
   * @notice Only callable by IMPORTER role when contract is not paused
   * @custom:requirement Recipient must be whitelisted
   */
  function imports(
    address to,
    uint120 brandId,
    WrapperInput[] calldata wrappers
  ) external payable whenNotPaused onlyRole(IMPORTER) onlyWhitelisted(to) {
    if (to == address(0)) revert ZeroAddress();
    if (wrappers.length == 0) revert EmptyInput();

    uint256 length = wrappers.length;
    Data[] memory data = new Data[](length);

    for (uint256 i; i < length; ) {
      WrapperInput calldata wrapper = wrappers[i];
      uint256 wrapperId = _wrapperIdCounter;

      data[i] = Data({ sku: wrapper.sku, wrapperId: wrapperId });
      Collection storage collection = _collections[brandId][wrapper.sku];

      _collections[brandId][wrapper.sku].wrappers[wrapperId] = Wrapper(
        wrapper.uri,
        wrapper.sku,
        wrapper.ids,
        brandId
      );

      collection.wrapperIds.add(wrapperId);
      _safeMint(to, wrapperId);

      unchecked {
        ++i;
        ++_wrapperIdCounter;
      }
    }

    emit Import(data, to);
  }

  /**
   * @dev Transfers multiple tokens to a single recipient
   * @param to Recipient address
   * @param tokenIds Array of token IDs to transfer
   * @notice Only callable by contract owner when not paused
   */
  function batchTransfer(
    address to,
    uint256[] calldata tokenIds
  ) external payable whenNotPaused onlyRole(OWNER) {
    if (to == address(0)) revert ZeroAddress();
    if (tokenIds.length == 0) revert EmptyInput();

    uint256 length = tokenIds.length;
    for (uint256 i; i < length; ) {
      _update(to, tokenIds[i], msg.sender);
      unchecked {
        ++i;
      }
    }

    emit BatchTransfer(msg.sender, to, tokenIds);
  }

  /**
   * @dev Handles marketplace-specific token transfers
   * @param from Current token owner
   * @param to New token owner
   * @param tokenId Token identifier
   * @notice Only callable by addresses with delegated roles when not paused
   */
  function marketplaceTransfer(
    address from,
    address to,
    uint tokenId
  ) external override whenNotPaused onlyDelegatedRole {
    if (from == address(0) || to == address(0)) revert ZeroAddress();
    _update(to, tokenId, from);
    emit MarketplaceTransfer(from, to, tokenId);
  }

  /**
   * @dev Internal function to update token ownership
   * @param to New token owner
   * @param tokenId Token identifier
   * @param auth Address authorized to make the transfer
   * @return address The new owner's address
   */
  function _update(
    address to,
    uint256 tokenId,
    address auth
  )
    internal
    override(ERC721Upgradeable, ERC721PausableUpgradeable)
    whenNotPaused
    returns (address)
  {
    return super._update(to, tokenId, auth);
  }

  /**
   * @dev Internal function to get brand ID and SKU for a wrapper
   * @param wrapperId Wrapper token ID
   * @return brandId Brand identifier
   * @return sku SKU identifier
   */
  function _getBrandIdAndSku(
    uint256 wrapperId
  ) internal view returns (uint256 brandId, bytes32 sku) {
    Wrapper storage wrapper = _collections[brandId][sku].wrappers[wrapperId];
    return (wrapper.brandId, wrapper.sku);
  }

  /**
   * @dev Implementation of the {IERC165} interface
   * @param interfaceId Interface identifier
   * @return bool True if interface is supported
   */
  function supportsInterface(
    bytes4 interfaceId
  ) public view override(ERC721Upgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /**
   * @dev Returns the URI for a given token ID
   * @param tokenId Token identifier
   * @return string Token URI
   */
  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    return getData(tokenId).uri;
  }

  /**
   * @dev Internal function to authorize contract upgrades
   * @param newImplementation Address of new implementation
   * @notice Only callable by addresses with UPGRADER role
   */
  function _authorizeUpgrade(
    address newImplementation
  ) internal view override onlyRole(UPGRADER) {
    if (newImplementation == address(0)) revert ZeroAddress();
  }
}
