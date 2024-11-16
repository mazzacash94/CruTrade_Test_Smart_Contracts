// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import './abstracts/Modifiers.sol';
import './interfaces/IPayments.sol';
import './abstracts/RolesVariables.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';

/**
 * @title Presale
 * @dev Implements a multi-round token presale system with upgradeable capabilities
 * Features include:
 * - Multiple presale rounds with different prices and supplies
 * - Whitelist functionality
 * - Signature verification
 * - Anti-reentrancy protection
 * - Role-based access control
 * - Emergency pause functionality
 * - Comprehensive event logging
 */
contract Presale is
    Initializable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    Modifiers
{
    // Token being sold in the presale
    IERC20 private crutoken;

    /**
     * @dev Structure defining a presale round
     * @param price Token price for the round
     * @param supply Total token supply allocated for the round
     * @param soldTokens Number of tokens sold in the round
     */
    struct Round {
        uint256 price;
        uint256 supply;
        uint256 soldTokens;
    }

    // Array storing all presale rounds
    Round[] private rounds;
    
    // Current active round index
    uint256 private currentRound;

    // Mapping to track user contributions
    mapping(address => uint256) public userContributions;

    // Events
    event Conversion(address indexed buyer, uint256 amount);
    event RoundAdded(uint256 indexed roundId, uint256 price, uint256 supply);
    event FundsWithdrawn(address indexed token, uint256 amount, address treasury);
    event PresalePaused(address indexed operator);
    event PresaleUnpaused(address indexed operator);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with token address and roles
     * @param _crutoken Address of the token being sold
     * @param _roles Address of the roles contract
     */
    function initialize(address _crutoken, address _roles) public initializer {
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Pausable_init();
        __Modifiers_init(_roles);

        crutoken = IERC20(_crutoken);

        // Set initial round parameters
        uint256 initialPrice = 100000; // 0.1 USDT (assuming 6 decimals for USDT)
        uint256 initialSupply = 1000000 * 1e18; // 1 million CRUT tokens

        rounds.push(
            Round({
                price: initialPrice,
                supply: initialSupply,
                soldTokens: 0
            })
        );

        emit RoundAdded(0, initialPrice, initialSupply);
    }

    /**
     * @dev Pauses the presale
     * Requirements:
     * - Caller must have PRESALER role
     */
    function pause() external onlyRole(PRESALER) {
        _pause();
        emit PresalePaused(msg.sender);
    }

    /**
     * @dev Unpauses the presale
     * Requirements:
     * - Caller must have PRESALER role
     */
    function unpause() external onlyRole(PRESALER) {
        _unpause();
        emit PresaleUnpaused(msg.sender);
    }

    /**
     * @dev Creates a new presale round
     * @param price Token price for the new round
     * @param supply Total token supply for the new round
     * Requirements:
     * - Caller must have PRESALER role
     * - Price must be greater than 0
     * - Supply must be greater than 0
     */
    function createRound(
        uint256 price,
        uint256 supply
    ) external onlyRole(PRESALER) whenNotPaused {
        require(price > 0, 'Price must be greater than 0');
        require(supply > 0, 'Supply must be greater than 0');

        rounds.push(Round({
            price: price,
            supply: supply,
            soldTokens: 0
        }));

        emit RoundAdded(rounds.length - 1, price, supply);
    }

    /**
     * @dev Handles token purchase in the current round
     * @param hash Verification hash
     * @param signature Signature for verification
     * @param account Buyer's address
     * @param erc20 Payment token address
     * @param amount Amount of tokens to purchase
     * Requirements:
     * - Current round must be active
     * - Valid signature
     * - Account must be whitelisted
     * - Caller must have PRESALER role
     * - Payment token must be valid
     * - Contract must not be paused
     */
    function purchase(
        bytes32 hash,
        bytes calldata signature,
        address account,
        address erc20,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
        onlyRole(PRESALER)
        onlyValidPayment(erc20)
        onlyWhitelisted(account)      
        checkSignature(account, hash, signature)         
    {
        require(currentRound < rounds.length, 'Presale ended');

        Round storage round = rounds[currentRound];

        uint256 tokensToBuy = (amount * 10);

        require(tokensToBuy > 0, 'Must buy at least 1 token');
        require(
            round.soldTokens + tokensToBuy <= round.supply,
            'Exceeds round supply'
        );

        IPayments(roles.getRoleAddress(PAYMENTS)).convert(account, erc20, amount);

        round.soldTokens += tokensToBuy;
        userContributions[account] += amount;

        emit Conversion(account, tokensToBuy);

        // Advance to next round if current round is completed
        if (round.soldTokens == round.supply) {
            currentRound++;
        }
    }

    /**
     * @dev Withdraws collected funds to treasury
     * @param erc20 Token address to withdraw
     * Requirements:
     * - Caller must have PRESALER role
     * - Contract must have positive balance
     */
    function recoverERC20(address erc20) external onlyRole(PRESALER) nonReentrant {
        IERC20 erc20Token = IERC20(erc20);
        uint256 balance = erc20Token.balanceOf(address(this));
        require(balance > 0, 'No funds to withdraw');
        
        address treasury = roles.getRoleAddress(TREASURY);
        require(erc20Token.transfer(treasury, balance), 'USDT transfer failed');
        
        emit FundsWithdrawn(erc20, balance, treasury);
    }

    /**
     * @dev Returns current active round index
     */
    function getCurrentRound() external view returns (uint256) {
        return currentRound;
    }

    /**
     * @dev Returns total number of rounds
     */
    function getTotalRounds() external view returns (uint256) {
        return rounds.length;
    }

    /**
     * @dev Returns information about a specific round
     * @param _roundId Round index to query
     * @return price Round price
     * @return supply Round total supply
     * @return soldTokens Number of tokens sold
     */
    function getRoundInfo(
        uint256 _roundId
    ) external view returns (uint256, uint256, uint256) {
        require(_roundId < rounds.length, 'Invalid round ID');
        Round storage round = rounds[_roundId];
        return (round.price, round.supply, round.soldTokens);
    }

    /**
     * @dev Returns total contribution of all users
     */
    function getTotalContributions() external view returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < rounds.length; i++) {
            total += rounds[i].soldTokens;
        }
        return total;
    }

    /**
     * @dev Authorization function for contract upgrades
     * @param newImplementation Address of new implementation
     * Requirements:
     * - Caller must have UPGRADER role
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER) {}
}