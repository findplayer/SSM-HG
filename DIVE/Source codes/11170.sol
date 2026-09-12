/*

 ____                         ____           
/\  _`\                      /\  _`\   __    
\ \ \L\_\     __       ____  \ \ \L\_\/\_\   
 \ \ \L_L   /'__`\    /',__\  \ \  _\/\/\ \  
  \ \ \/, \/\ \L\.\_ /\__, `\  \ \ \/  \ \ \ 
   \ \____/\ \__/.\_\\/\____/   \ \_\   \ \_\
    \/___/  \/__/\/_/ \/___/     \/_/    \/_/
                                             

GasFi introduces a paradigm shift in DeFi trading by tokenizing multi-chain gas as a tradable asset. 
Drawing parallels with the emergence of futures contracts in the 19th century, 
GasFi extends these principles to the burgeoning field of digital assets, focusing on blockchain gas fees. 
Our vision is to establish a versatile platform for users to hedge against gas fee volatility, 
introducing an innovative dimension to cryptocurrency financial products.

Website:    https://gasfi.io/
Telegram:   https://t.me/GASFI_Portal
Twitter:    https://twitter.com/GASFI_Official
Whitepaper: https://gasfi.gitbook.io/

*/

// SPDX-License-Identifier: MIT

// File: lib/@openzeppelin/contracts/utils/ReentrancyGuard.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/ReentrancyGuard.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant NOT_ENTERED = 1;
    uint256 private constant ENTERED = 2;

    uint256 private _status;

    /**
     * @dev Unauthorized reentrant call.
     */
    error ReentrancyGuardReentrantCall();

    constructor() {
        _status = NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be NOT_ENTERED
        if (_status == ENTERED) {
            revert ReentrancyGuardReentrantCall();
        }

        // Any calls to nonReentrant after this point will fail
        _status = ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == ENTERED;
    }
}

// File: src/GasFi.sol


pragma solidity ^0.8.13;

//import {Test, console2} from "forge-std/Test.sol";

contract GasFi is ReentrancyGuard {
// y=(G+L) * (1-f ) * (x /G )
    struct Pool {
        uint256 height; //
        uint256 biggerAmount; //by wei
        uint256 lessAmount; //by wei
        uint256 gas;  //gas price by wei
        address creator;
        uint32 poolFee; // 1~30 = 0.1% ~ 3 %
        uint16 isExtracted; //
        uint16 result; //       0:pool not open 1: less than pool gas price 2: bigger than pool gas price 3: equals to pool gas
        uint32 projectFee;
    }

    struct Bet {
        uint256 amount; // by wei
//        uint poolId;
        address creator;
        uint32 isBigger;
        uint32 isExtracted;
    }

    enum PoolStatus{
        Active,
        Locked,
        Opened,
        Extracted
    }

    enum BetStatus{
        Active,
        Locked,
        Win,
        Extracted,
        NotWin,
        Tie
    }

    event PoolCreated(uint poolId, uint height, uint256 gas, uint biggerAmount, uint lessAmount, uint32 poolFee, address creator, uint betIdBigger, uint betIdLess);

    event BetCreated(uint poolId, uint betValue, uint32 isBigger, uint biggerAmount, uint lessAmount, address creator, uint betId);

    event BetAppended(uint poolId, uint betValue, uint32 isBigger, uint biggerAmount, uint lessAmount, address creator, uint betId);

    event PoolOpened(uint poolId, uint16 result);

    event BetExtracted(uint poolId, uint betId, uint256 value, address extractor);

    event PoolExtracted(uint poolId, uint fee, address extractor);


    uint constant public FEE_DECIMAL = 1000;
    address immutable public owner;
    address immutable public resultSetter;

    uint  public minPoolFee = 1; // 0.1%
    uint  public maxPoolFee = 30; //3%
    uint32  public projectFee = 50; //5%

    uint256 public latestPoolId;
    uint256 public latestBetId;
    uint public lockedBlockHeight = 149; // 30min
    uint public minPoolSize = 0.166 ether;

    mapping(uint256 => Pool) public pools_;
    mapping(uint256 => mapping(uint256 => Bet)) public bets_;

    constructor(address _resultSetter){
        owner = msg.sender;
        resultSetter = _resultSetter;
    }

    function setLockedBlockHeight(uint _lockedBlockHeight) external {
        assert(msg.sender == resultSetter);
        lockedBlockHeight = _lockedBlockHeight;
    }

    function setMinPoolSize(uint _minPoolSize) external {
        assert(msg.sender == resultSetter);
        minPoolSize = _minPoolSize;
    }

    function setMinPoolFee(uint _minPoolFee) external {
        assert(msg.sender == resultSetter);
        minPoolFee = _minPoolFee;
    }

    function setMaxPoolFee(uint _maxPoolFee) external {
        assert(msg.sender == resultSetter);
        maxPoolFee = _maxPoolFee;
    }

    function setProjectFee(uint32 _projectFee) external {
        assert(msg.sender == resultSetter);
        projectFee = _projectFee;
    }

    function createPool(uint blockNumber, uint256 gas, uint initialValue, uint32 poolFee) external payable {
        require(blockNumber > block.number, "createPool::invalid block number");
//        require(gas > 0, "createPool::invalid gas price");
        require(msg.value >= initialValue, "createPool::value not enough ");
        require(initialValue >= minPoolSize, "createPool::size too little ");
        require(poolFee >= minPoolFee && poolFee <= maxPoolFee, "createPool::invalid poolFee");

        Pool storage pool = pools_[++latestPoolId];
        pool.height = blockNumber;
        pool.creator = msg.sender;
        pool.gas = gas;
        pool.poolFee = poolFee;
        pool.projectFee = projectFee;
        uint betValue = initialValue / 2;

        pool.biggerAmount = betValue;
        pool.lessAmount = betValue;
        uint betIdLess = _makeBet(latestPoolId, betValue, 0);
        uint betIdBigger = _makeBet(latestPoolId, betValue, 1);

        emit PoolCreated(latestPoolId, blockNumber, gas, betValue, betValue, poolFee, msg.sender, betIdBigger, betIdLess);
        emit BetCreated(latestPoolId, betValue, 1, betValue, 0, msg.sender, betIdBigger);
        emit BetCreated(latestPoolId, betValue, 0, betValue, betValue, msg.sender, betIdLess);


    }


    function makeBet(uint poolId, uint betValue, uint32 isBigger) external payable {
        require(poolId <= latestPoolId && poolId != 0, "makeBet::invalid pool id");
        require(msg.value >= betValue, "makeBet::value not enough");
        require(isBigger == 0 || isBigger == 1, "makeBet::invalid isBigger");

        uint betId = _makeBet(poolId, betValue, isBigger);

        Pool storage pool = pools_[poolId];
        require(_poolStatus(pool) == PoolStatus.Active, "makeBet::pool is locked ");
        if (isBigger == 0) {
            pool.lessAmount += betValue;
        }
        if (isBigger == 1) {
            pool.biggerAmount += betValue;
        }
        emit BetCreated(poolId, betValue, isBigger, pool.biggerAmount, pool.lessAmount, msg.sender, betId);
    }

    function appendBet(uint _poolId, uint256 _betId, uint appendValue) external payable {
        require(_poolId <= latestPoolId && _poolId != 0, "appendBet::invalid pool id");
        require(_betId <= latestBetId && _betId != 0, "betStatus::invalid bet id");
        require(msg.value >= appendValue, "appendBet::value not enough");

        Bet storage bet = bets_[_poolId][_betId];
        require(bet.creator == msg.sender, "appendBet::invalid sender");
        Pool storage pool = pools_[_poolId];
        require(_betStatus(pool, bet) == BetStatus.Active, "appendBet::bet is not active");

        bet.amount += appendValue;
        uint32 isBigger = bet.isBigger;
        if (isBigger == 0) {
            pool.lessAmount += appendValue;
        }
        if (isBigger == 1) {
            pool.biggerAmount += appendValue;
        }

        emit BetAppended(_poolId, appendValue, isBigger, pool.biggerAmount, pool.lessAmount, msg.sender, _betId);
    }

    //
    function setResults(uint[] memory _poolIds, uint16[] memory _results) external {
        assert(msg.sender == resultSetter);
        for (uint i = 0; i < _results.length; i++) {
            uint _poolId = _poolIds[i];
            uint16 _result = _results[i];
            Pool storage pool = pools_[_poolId];
            pool.result = _result;
            emit PoolOpened(_poolId, _result);
        }
    }

    function withdrawPool(uint _poolId, uint biggerBetId, uint lessBetId) external nonReentrant {
        require(_poolId <= latestPoolId && _poolId != 0, "withdrawPool::invalid pool id");
        Pool storage pool = pools_[_poolId];
        require(_poolStatus(pool) == PoolStatus.Opened, "withdrawPool::pool is not opened");
        require(msg.sender == pool.creator, "withdrawPool::wrong sender");

        pool.isExtracted = 1;
        uint256 fee = (pool.lessAmount + pool.biggerAmount) * pool.poolFee / FEE_DECIMAL;

        uint biggerValue = _getBetWithdrawValue(_poolId, biggerBetId);
        Bet  storage biggerBet = bets_[_poolId][biggerBetId];
        biggerBet.isExtracted = 1;

        uint lessValue = _getBetWithdrawValue(_poolId, lessBetId);
        Bet  storage lessBet = bets_[_poolId][lessBetId];
        lessBet.isExtracted = 1;

        (bool sent,) = payable(msg.sender).call{value: fee + biggerValue + lessValue}("");
        require(sent, "withdrawPool::Failed to send Ether");

        if (biggerValue != 0) {
            emit BetExtracted(_poolId, biggerBetId, biggerValue, msg.sender);
        }
        if (lessValue != 0) {
            emit BetExtracted(_poolId, lessBetId, lessValue, msg.sender);
        }
        emit PoolExtracted(_poolId, fee, msg.sender);

    }

// y=(G+L) * (1-f ) * (x /G )
    function withdrawBet(uint _poolId, uint _betId) external nonReentrant {
        _withdrawBet(_poolId, _betId);
    }

    function withdrawBets(uint[] memory _poolIds, uint[] memory _betIds) external nonReentrant {
        require(_poolIds.length == _betIds.length, "withdrawBets::wrong args");
        for (uint i = 0; i < _poolIds.length; ++i) {
            _withdrawBet(_poolIds[i], _betIds[i]);
        }
    }

    function _withdrawBet(uint _poolId, uint _betId) internal {
        require(_poolId <= latestPoolId && _poolId != 0, "withdrawBet::invalid pool id");

//        require(poolStatus(_poolId) == PoolStatus.Win || poolStatus(_poolId) == PoolStatus.Extracted, "withdrawBet::pool is not opened");
        uint value = _getBetWithdrawValue(_poolId, _betId);
        require(value > 0, "_withdrawBet::not winner");
        Bet  storage biggerBet = bets_[_poolId][_betId];
        biggerBet.isExtracted = 1;
//        console2.log(address(this).balance);
//        console2.log(value);
        (bool sent,) = payable(msg.sender).call{value: value}("");
//        console2.log(sent);
        require(sent, "_withdrawBet::send fail");

        emit BetExtracted(_poolId, _betId, value, msg.sender);
    }


    function withdrawFee(address to, uint amount) external {
        assert(msg.sender == owner);
        (bool sent,) = payable(to).call{value: amount}("");
        assert(sent);
    }


    function poolStatus(uint256 _poolId) external view returns (PoolStatus) {
        require(_poolId <= latestPoolId && _poolId != 0, "poolStatus::invalid pool id");
        Pool memory pool = pools_[_poolId];
        if (pool.isExtracted == 1) {
            return PoolStatus.Extracted;
        }
        if (pool.result > 0) {
            return PoolStatus.Opened;
        }
        if (pool.height <= lockedBlockHeight + block.number) {
            return PoolStatus.Locked;
        }
        return PoolStatus.Active;
    }

    function _poolStatus(Pool memory pool) internal view returns (PoolStatus) {
//        require(_poolId <= latestPoolId && _poolId != 0, "poolStatus::invalid pool id");
//        Pool memory pool = pools_[_poolId];
        if (pool.isExtracted == 1) {
            return PoolStatus.Extracted;
        }
        if (pool.result > 0) {
            return PoolStatus.Opened;
        }
        if (pool.height <= lockedBlockHeight + block.number) {
            return PoolStatus.Locked;
        }
        return PoolStatus.Active;
    }

    function betStatus(uint _poolId, uint256 _betId) external view returns (BetStatus) {
//        require(_poolId <= latestPoolId && _poolId != 0, "betStatus::invalid pool id");
//        require(_betId <= latestBetId && _betId != 0, "betStatus::invalid bet id");

        Bet memory bet = bets_[_poolId][_betId];
        require(bet.creator != address(0), "betStatus::invalid bet ");
        if (bet.isExtracted == 1) {
            return BetStatus.Extracted;
        }
        Pool memory pool = pools_[_poolId];
        uint16 result = pool.result;
        if (result > 0) {
            if (result == 3) {
                return BetStatus.Tie;
            }
            if (result - 1 == bet.isBigger) {
                return BetStatus.Win;
            }
            return BetStatus.NotWin;
        }
        if (pool.height <= lockedBlockHeight + block.number) {
            return BetStatus.Locked;
        }
        return BetStatus.Active;
    }

    function _betStatus(Pool memory pool, Bet memory bet) internal view returns (BetStatus) {
//        require(_poolId <= latestPoolId && _poolId != 0, "betStatus::invalid pool id");
//        require(_betId <= latestBetId && _betId != 0, "betStatus::invalid bet id");

//        Bet memory bet = bets_[_poolId][_betId];
//        require(bet.creator != address(0), "betStatus::invalid bet ");
        if (bet.isExtracted == 1) {
            return BetStatus.Extracted;
        }
        uint16 result = pool.result;
        if (result > 0) {
            if (result == 3) {
                return BetStatus.Tie;
            }
            if (result - 1 == bet.isBigger) {
                return BetStatus.Win;
            }
            return BetStatus.NotWin;
        }
        if (pool.height <= lockedBlockHeight + block.number) {
            return BetStatus.Locked;
        }
        return BetStatus.Active;
    }

    function getOdds(uint _poolId) external view returns (uint biggerOdds, uint lessOdds) {
// y=(G+L) * (1-f ) * (x /G )
//y/x = (1 + L/G)(1-f)
//y/x = (1 + L/G)(1-f)
        Pool memory pool = pools_[_poolId];
        uint fee = 1000 - (pool.poolFee + pool.projectFee);

        biggerOdds = (pool.biggerAmount + pool.lessAmount) * fee /  pool.biggerAmount;
        lessOdds = (pool.lessAmount + pool.biggerAmount) * fee / pool.lessAmount;
    }

    function _makeBet(uint poolId, uint betValue, uint32 isBigger) internal returns (uint) {

        Bet storage bet = bets_[poolId][++latestBetId];
        bet.amount = betValue;
        bet.creator = msg.sender;
        bet.isBigger = isBigger;
        return latestBetId;
    }

    function _getBetWithdrawValue(uint _poolId, uint _betId) internal view returns (uint) {
        require(_betId <= latestBetId && _betId != 0, "_getBetWithdrawValue::invalid bet id");
        Bet memory bet = bets_[_poolId][_betId];
        require(bet.creator == msg.sender, "_getBetWithdrawValue::invalid sender ");
        Pool memory pool = pools_[_poolId];
        require(_betStatus(pool, bet) == BetStatus.Win || _betStatus(pool, bet) == BetStatus.NotWin || _betStatus(pool, bet) == BetStatus.Tie, "_getBetWithdrawValue::not opened");


        uint16 result = pool.result;
        uint withoutFee = FEE_DECIMAL - (pool.projectFee + pool.poolFee);
        uint256 value;

        if (result == 3) {
            value = bet.amount * withoutFee / FEE_DECIMAL;
        }
        uint32 isBigger = bet.isBigger;
        if (isBigger + 1 == result) {
            uint256 lessAmount = pool.lessAmount;
            uint256 biggerAmount = pool.biggerAmount;
            // y=(G+L) * (1-f ) * (x /G )
            if (isBigger == 0) {
                value = (lessAmount + biggerAmount) * withoutFee * bet.amount / (lessAmount * FEE_DECIMAL);
            }
            if (isBigger == 1) {
                value = (lessAmount + biggerAmount) * withoutFee * bet.amount / (biggerAmount * FEE_DECIMAL);
            }
        }
        return value;
    }

    function getBetWithdrawValue(uint _poolId, uint _betId) external view returns (uint) {
        require(_betId <= latestBetId && _betId != 0, "_getBetWithdrawValue::invalid bet id");
        Bet memory bet = bets_[_poolId][_betId];
//        require(bet.creator == msg.sender, "_getBetWithdrawValue::invalid sender ");
        Pool memory pool = pools_[_poolId];
//        require(_betStatus(pool, bet) == BetStatus.Win || _betStatus(pool, bet) == BetStatus.NotWin || _betStatus(pool, bet) == BetStatus.Tie, "_getBetWithdrawValue::not opened");


        uint16 result = pool.result;
        uint withoutFee = FEE_DECIMAL - (pool.projectFee + pool.poolFee);
        uint256 value;

        if (result == 3) {
            value = bet.amount * withoutFee / FEE_DECIMAL;
        }
        uint32 isBigger = bet.isBigger;
        if (isBigger + 1 == result) {
            uint256 lessAmount = pool.lessAmount;
            uint256 biggerAmount = pool.biggerAmount;
            // y=(G+L) * (1-f ) * (x /G )
            if (isBigger == 0) {
                value = (lessAmount + biggerAmount) * withoutFee * bet.amount / (lessAmount * FEE_DECIMAL);
            }
            if (isBigger == 1) {
                value = (lessAmount + biggerAmount) * withoutFee * bet.amount / (biggerAmount * FEE_DECIMAL);
            }
        }
        return value;
    }
}