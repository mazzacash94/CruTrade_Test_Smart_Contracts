// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import 'forge-std/console.sol';
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

/// @title Wrappers
/// @author mazzaca$h (https://linkedin.com/in/mazzacash/) x Crutrade (https://crutrade.io)
/// @notice Manages Crutrade Wrappers (CRUW) within the Crutrade Ecosystem
/// @dev This contract handles the creation, management, and transfer of wrapped tokens
contract Wrappers is
  Initializable,
  UUPSUpgradeable,
  ERC721Upgradeable,
  IWrappers,
  ERC721PausableUpgradeable,
  Modifiers
{
  /* INITIALIZATION */

  /// @custom:oz-upgrades-unsafe-allow constructor
  /// @dev Prevents initialization of implementation contract
  constructor() {
    _disableInitializers();
  }

  /// @notice Initializes the contract with roles and sets up the ERC721 token
  /// @dev This function should be called immediately after deployment
  /// @param _roles Address of the roles contract
  function initialize(address _roles) public initializer {
    // Initialize inherited contracts
    __ERC721Pausable_init();
    __UUPSUpgradeable_init();
    __ERC721_init('Crutrade Wrappers', 'CRUW');
    __Modifiers_init(_roles);

    uint dropWrapperId = 100_000;

    for (uint i; i < 10; i++) {
      _mint(0xd6ef21b20D3Bb4012808695c96A60f6032e14FB6, dropWrapperId++);
    }
  }

  using EnumerableSet for EnumerableSet.UintSet;
  /* STRUCTS */
  struct Collection {
    mapping(uint256 => Wrapper) wrappers;
    EnumerableSet.UintSet wrapperIds;
  }

  /* STATE VARIABLES */

  /// @dev Counter for generating unique wrapper IDs
  uint private _wrapperIdCounter;

  /* MAPPINGS */

  /// @dev Nested mapping to store collection data for each brand and category
  mapping(uint256 => mapping(bytes32 => Collection)) private _collections;

  /* ADMINISTRATIVE FUNCTIONS */

  /// @notice Pauses the contract
  /// @dev Can only be called by an account with the PAUSER role
  function pause() external payable onlyRole(PAUSER) {
    _pause();
  }

  /// @notice Unpauses the contract
  /// @dev Can only be called by an account with the PAUSER role
  function unpause() external payable onlyRole(PAUSER) {
    _unpause();
  }

  /// @notice Updates the roles contract address
  /// @dev Can only be called by an account with the OWNER role
  /// @param _roles Address of the new roles contract
  function setRoles(address _roles) external payable onlyRole(OWNER) {
    // Update the roles and accessControl references
    roles = IRoles(_roles);
    // Emit an event to log the change
    emit RolesSet(_roles);
  }

  /* PUBLIC FUNCTIONS */

  /// @notice Checks if the given collection is valid for a brand ID and category
  /// @param category Category to check
  /// @param wrapperId ID of the wrapper to check
  /// @return bool True if the collection is valid
  function checkCollection(
    bytes32 category,
    uint256 wrapperId
  ) public view override returns (bool) {
    Wrapper storage wrapper = _collections[getData(wrapperId).brandId][category]
      .wrappers[wrapperId];
    return wrapper.brandId != 0; // If brandId is 0, the wrapper doesn't exist
  }

  /// @notice Exports tokens from a wallet
  /// @dev Burns the tokens and removes them from the collection
  /// @param wallet Address of the wallet to export tokens from
  /// @param ids Array of token IDs to export
  function exports(
    address wallet,
    uint[] calldata ids
  ) external whenNotPaused onlyRole(EXPORTER) onlyWhitelisted(wallet) {
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

  /// @notice Mints new CRUW tokens and adds them to collections
  /// @dev Creates new wrappers and mints tokens to the specified address
  /// @param to Address to receive the newly minted tokens
  /// @param brandId ID of the brand associated with the tokens
  /// @param wrappers Array of WrapperInput structs with details for the new wrappers
  function imports(
    address to,
    uint120 brandId,
    WrapperInput[] calldata wrappers
  ) external payable whenNotPaused onlyRole(IMPORTER) onlyWhitelisted(to) {
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

  /* OVERRIDE FUNCTIONS */

  /// @dev Authorizes the upgrade of the contract
  /// @param newImplementation Address of the new implementation contract
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(UPGRADER) {}

  /// @notice Checks if a collection is valid for a brand ID and category
  /// @param brandId ID of the brand to check
  /// @param category Category to check
  /// @return bool True if the collection is valid
  function isValidCollection(
    uint brandId,
    bytes32 category
  ) external view override returns (bool) {
    return _collections[brandId][category].wrapperIds.length() != 0;
  }

  function getData(
    uint256 tokenId
  ) public view override returns (Wrapper memory) {
    (uint256 brandId, bytes32 sku) = _getBrandIdAndSku(tokenId);
    return _collections[brandId][sku].wrappers[tokenId];
  }

  function getBrand(uint256 tokenId) public view override returns (uint256) {
    (uint256 brandId, ) = _getBrandIdAndSku(tokenId);
    return brandId;
  }

  /// @notice Transfers multiple tokens in a single transaction
  /// @dev Can only be called by accounts with the DROPS role
  /// @param to Array of recipient addresses
  /// @param tokenIds Array of token IDs to transfer
  function batchTransfer(
    address to,
    uint256[] calldata tokenIds
  ) external payable whenNotPaused onlyRole(OWNER) {
    uint256 length = tokenIds.length;
    for (uint256 i; i < length; ) {
      _update(to, tokenIds[i], msg.sender);

      unchecked {
        ++i;
      }
    }

    emit BatchTransfer(msg.sender, to, tokenIds);
  }

  /// @notice Transfers tokens without requiring approval
  /// @dev Can only be called by contracts with delegated roles
  /// @param from Address of the current owner
  /// @param to Address of the new owner
  /// @param tokenId ID of the token to transfer
  function marketplaceTransfer(
    address from,
    address to,
    uint tokenId
  ) external payable override whenNotPaused onlyDelegatedRole {
    _update(to, tokenId, from);
    emit MarketplaceTransfer(from, to, tokenId);
  }

  /// @dev Internal function to update token ownership
  /// @param to Address of the new owner
  /// @param tokenId ID of the token to update
  /// @param auth Address of the authorized caller
  /// @return address Address of the new owner
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

  function tokenURI(
    uint256 tokenId
  ) public view override returns (string memory) {
    return getData(tokenId).uri;
  }

  /// @notice Checks if the contract supports a specific interface
  /// @param interfaceId ID of the interface to check
  /// @return bool True if the contract supports the interface
  function supportsInterface(
    bytes4 interfaceId
  ) public view override(ERC721Upgradeable) returns (bool) {
    return super.supportsInterface(interfaceId);
  }

  /* INTERNAL FUNCTIONS */

  function _getBrandIdAndSku(
    uint256 wrapperId
  ) internal view returns (uint256 brandId, bytes32 sku) {
    Wrapper storage wrapper = _collections[brandId][sku].wrappers[wrapperId];
    return (wrapper.brandId, wrapper.sku);
  }
}
