// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import './abstracts/Modifiers.sol';
import './abstracts/RolesVariables.sol';
import './interfaces/IPayments.sol';

contract Presale is
  Initializable,
  ReentrancyGuardUpgradeable,
  UUPSUpgradeable,
  Modifiers
{
  IERC20 public crutoken;
  IERC20 public usdt;

  struct Round {
    uint256 price;
    uint256 supply;
    uint256 startTime;
    uint256 endTime;
    uint256 soldTokens;
  }

  Round[] public rounds;
  uint256 public currentRound;

  mapping(address => uint256) public userContributions;

  event Conversion(address indexed buyer, uint256 amount);
  event RoundAdded(
    uint256 roundId,
    uint256 price,
    uint256 supply,
    uint256 startTime,
    uint256 endTime
  );

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(address _crutoken, address _roles) public initializer {
    __ReentrancyGuard_init();
    __UUPSUpgradeable_init();
    __Modifiers_init(_roles);

    crutoken = IERC20(_crutoken);

    // Set initial round
    uint256 initialPrice = 100000; // 0.1 USDT (assuming 6 decimals for USDT)
    uint256 initialSupply = 1000000 * 1e18; // 1 million CRUT tokens
    uint256 startTime = block.timestamp;
    uint256 endTime = startTime + 30 days;

    rounds.push(
      Round({
        price: initialPrice,
        supply: initialSupply,
        startTime: startTime,
        endTime: endTime,
        soldTokens: 0
      })
    );

    emit RoundAdded(0, initialPrice, initialSupply, startTime, endTime);
  }

  function addRound(
    uint256 _price,
    uint256 _supply,
    uint256 _startTime,
    uint256 _endTime
  ) external onlyRole(PRESALER) {
    require(_startTime < _endTime, 'Invalid time range');
    require(_price > 0, 'Price must be greater than 0');
    require(_supply > 0, 'Supply must be greater than 0');

    rounds.push(
      Round({
        price: _price,
        supply: _supply,
        startTime: _startTime,
        endTime: _endTime,
        soldTokens: 0
      })
    );

    emit RoundAdded(rounds.length - 1, _price, _supply, _startTime, _endTime);
  }

  function convert(
    bytes32 hash,
    bytes calldata signature,
    address account,
    address erc20,
    uint256 amount
  )
    external
    nonReentrant
    checkSignature(account, hash, signature)
    onlyWhitelisted(account)
    onlyRole(PRESALER)
  {
    require(currentRound < rounds.length, 'Presale ended');

    Round storage round = rounds[currentRound];
    require(
      block.timestamp >= round.startTime && block.timestamp <= round.endTime,
      'Round not active'
    );

    uint256 tokensToBuy = (amount * 10);

    require(tokensToBuy > 0, 'Must buy at least 1 token');
    require(
      round.soldTokens + tokensToBuy <= round.supply,
      'Exceeds round supply'
    );

    IPayments(roles.getRoleAddress(PAYMENTS)).swap(account, erc20, amount);

    round.soldTokens += tokensToBuy;
    userContributions[account] += amount;

    emit Conversion(account, tokensToBuy);

    if (round.soldTokens == round.supply) {
      currentRound++;
    }
  }

  function withdrawFunds() external onlyRole(PRESALER) {
    uint256 balance = usdt.balanceOf(address(this));
    require(balance > 0, 'No funds to withdraw');
    address treasury = roles.getRoleAddress(TREASURY);
    require(usdt.transfer(treasury, balance), 'USDT transfer failed');
  }

  function getCurrentRound() external view returns (uint256) {
    return currentRound;
  }

  function getRoundInfo(
    uint256 _roundId
  ) external view returns (uint256, uint256, uint256, uint256, uint256) {
    require(_roundId < rounds.length, 'Invalid round ID');
    Round storage round = rounds[_roundId];
    return (
      round.price,
      round.supply,
      round.startTime,
      round.endTime,
      round.soldTokens
    );
  }

  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyRole(UPGRADER) {}
}
