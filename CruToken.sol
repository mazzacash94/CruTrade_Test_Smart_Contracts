// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";

/*
========================================================================================
      ______                       ________            __                           
     /      \                     |        \          |  \                          
    |  $$$$$$\  ______   __    __  \$$$$$$$$  ______  | $$   __   ______   _______  
    | $$   \$$ /      \ |  \  |  \   | $$    /      \ | $$  /  \ /      \ |       \ 
    | $$      |  $$$$$$\| $$  | $$   | $$   |  $$$$$$\| $$_/  $$|  $$$$$$\| $$$$$$$\
    | $$   __ | $$   \$$| $$  | $$   | $$   | $$  | $$| $$   $$ | $$    $$| $$  | $$
    | $$__/  \| $$      | $$__/ $$   | $$   | $$__/ $$| $$$$$$\ | $$$$$$$$| $$  | $$
     \$$    $$| $$       \$$    $$   | $$    \$$    $$| $$  \$$\ \$$     \| $$  | $$
      \$$$$$$  \$$        \$$$$$$     \$$     \$$$$$$  \$$   \$$  \$$$$$$$ \$$   \$$

========================================================================================

    @title       CruToken  - (CRU) - Utility Token
    @custom:web  CruTrade  - https://crutrade.io 
    @author      mazzaca$h - https://linkedin.com/in/mazzacash
  
    @notice      Advanced ERC20 powering the CruTrade ecosystem
                 • Fixed supply utility token with membership perks
                 • Platform benefits and fee optimizations
                 • Recovery system for external tokens
  
    @dev         Built on OpenZeppelin with enhanced features:
                 • Secure asset recovery for external tokens
                 • Emergency circuit breakers
                 • ERC20 Permit for gasless operations
                 • Battle-tested by industry standards
 
    @custom:security-contact security@crutrade.io
========================================================================================
 */
contract CruToken is ERC20, ERC20Pausable, Ownable, ERC20Permit {
    using SafeERC20 for IERC20;

    /* ========== ERRORS ========== */

    /// @notice Thrown when a required amount parameter is zero
    error ZeroAmount(uint256 provided);

    /// @notice Thrown when a required address parameter is zero
    error ZeroAddress(address provided);

    /// @notice Thrown when an amount exceeds available balance
    error InvalidAmount(uint256 requested, uint256 available);

    /// @notice Thrown when recovery amount exceeds contract balance
    error InsufficientRecoveryBalance(
        address token,
        uint256 requested,
        uint256 available
    );

    /* ========== EVENTS ========== */

    /// @notice Emitted when tokens are recovered from the contract
    /// @param token Address of the recovered token contract
    /// @param amount Number of tokens recovered
    event TokensRecovered(address indexed token, uint256 amount);

    /* ========== CONSTRUCTOR ========== */

    /**
     * @notice Deploys CruToken with fixed supply
     * @param initialOwner Address that will own the contract and receive initial supply
     * @dev Mints total supply to owner address and initializes all OpenZeppelin features
     * @custom:security Non-zero address check implemented with custom error
     */
    constructor(address initialOwner)
        ERC20("CruToken", "CRU")
        Ownable(initialOwner)
        ERC20Permit("CruToken")
    {
        require(initialOwner != address(0), ZeroAddress(initialOwner));
        _mint(initialOwner, 1_000_000_000 * 10**decimals());
    }

    /* ========== CIRCUIT BREAKERS ========== */

    /**
     * @notice Emergency pause mechanism to stop all transfers
     * @dev Leverages OpenZeppelin's _pause() implementation
     * @custom:security Only callable by owner via Ownable modifier
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Resume normal transfer operations
     * @dev Leverages OpenZeppelin's _unpause() implementation
     * @custom:security Only callable by owner via Ownable modifier
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /* ========== RECOVERY ========== */

    /**
     * @notice Recovers ERC20 tokens accidentally sent to contract
     * @dev Uses SafeERC20 for secure token transfers
     * @param tokenAddress Address of token contract to recover
     * @param amount Number of tokens to recover
     * @custom:security
     * - Only callable by owner via Ownable modifier
     * - Checks for zero amount with custom error
     * - Validates sufficient balance before transfer
     * - Uses SafeERC20 for secure transfers
     */
    function recoverERC20(address tokenAddress, uint256 amount)
        external
        onlyOwner
    {
        require(amount > 0, ZeroAmount(amount));

        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));

        require(
            balance >= amount,
            InsufficientRecoveryBalance(tokenAddress, amount, balance)
        );

        token.safeTransfer(owner(), amount);
        emit TokensRecovered(tokenAddress, amount);
    }

    /* ========== INTERNAL ========== */

    /**
     * @notice Extended transfer logic including pause check
     * @dev Overrides both ERC20 and ERC20Pausable _update
     * @param from Address sending tokens
     * @param to Address receiving tokens
     * @param value Amount of tokens being transferred
     * @custom:security Includes OpenZeppelin's pausable check for transfers
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable) {
        super._update(from, to, value);
    }
}
