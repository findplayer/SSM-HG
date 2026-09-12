// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () { }
    // solhint-disable-previous-line no-empty-blocks

    function _msgSender() internal view returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface Token {
    function transferFrom(address, address, uint) external returns (bool);
    function transfer(address, uint) external returns (bool);
    function balanceOf(address tokenOwner) external returns (uint);
}

contract Staking is Ownable {
    using SafeMath for uint256;
    
    event RewardsTransferred(address holder, uint256 amount);
    
    //total tokens staked
    uint256 public totalstaked = 0;
    address public devAddress = 0x79259A5029a75dA58b929d2f411F7420A5dCfb6A;
    // bunny token contract...
    address public bunny = 0x926568b7AA2ccB9D5d4279c5A046c6Dc00af026E;
    
    // reward interval 365 days
    uint256 public rewardInterval = 365 days;
    uint256 public totalClaimedRewards;

    uint256 public MinimumWithdrawTime = 5 days;
    uint256 public MinimumWithdrawTime2 = 10 days;
    uint256 public MinimumWithdrawTime3 = 15 days;
    
    mapping (address => uint256) public depositedTokens;
    mapping (address => uint256) public stakingTime;
    mapping (address => uint256) public lastClaimedTime;
    mapping (address => uint256) public totalEarnedTokens;
    mapping (address => uint256) public timeperiod;
    
    function updateAccount(address account) private {

        uint256 pendingDivs = getPendingDivs(account);
        lastClaimedTime[account] = block.timestamp;

        if (pendingDivs != 0) {
            totalEarnedTokens[account] = totalEarnedTokens[account].add(pendingDivs);
            totalClaimedRewards = totalClaimedRewards.add(pendingDivs);

            Token(bunny).transfer(account, pendingDivs);
            emit RewardsTransferred(account, pendingDivs);
        }
    }
    
    function getPendingDivs(address _holder) public view returns (uint256 _pendingDivs) {
        
        uint256 timeDiff = block.timestamp.sub(lastClaimedTime[_holder]);
        uint256 stakedAmount = depositedTokens[_holder];
        uint256 rrate;

        if (timeperiod[_holder] == 15) rrate = 700;
        if (timeperiod[_holder] == 10) rrate = 400;
        if (timeperiod[_holder] == 5) rrate = 150;

        uint256 pendingDivs = stakedAmount.mul(rrate).mul(timeDiff).div(rewardInterval).div(1e2);
        return pendingDivs;
    }
    
    function deposit(uint256 amountToStake, uint256 _timeperiod) public {

       require(_timeperiod == 5 || _timeperiod == 10 || _timeperiod == 15, "Invalid Time Period. it must be either 7 or 15"); 
        
        Token(bunny).transferFrom(msg.sender, address(this), amountToStake);
        timeperiod[msg.sender] = _timeperiod;
        updateAccount(msg.sender);
        stakingTime[msg.sender] = block.timestamp;
        depositedTokens[msg.sender] = depositedTokens[msg.sender].add(amountToStake);
        totalstaked = totalstaked.add(amountToStake);
       
    }
    
    function withdraw(uint256 amountToWithdraw) public {
        require(depositedTokens[msg.sender] >= amountToWithdraw, "Invalid amount to withdraw");

        depositedTokens[msg.sender] = depositedTokens[msg.sender].sub(amountToWithdraw);
        totalstaked = totalstaked.sub(amountToWithdraw);

        updateAccount(msg.sender);


        uint256 _lastClaimedTime = block.timestamp.sub(stakingTime[msg.sender]);

        if (timeperiod[msg.sender] == 5){
        if (_lastClaimedTime >= MinimumWithdrawTime) {
            require(Token(bunny).transfer(msg.sender, amountToWithdraw), "Could not transfer tokens.");
        }
        
        if (_lastClaimedTime < MinimumWithdrawTime) {
            uint256 WithdrawFee = amountToWithdraw.div(1e2).mul(5);
            uint256 amountAfterFee = amountToWithdraw.sub(WithdrawFee);
            require(Token(bunny).transfer(msg.sender, amountAfterFee), "Could not transfer tokens.");
            require(Token(bunny).transfer(devAddress, WithdrawFee), "Could not transfer tokens.");
        }}

        if (timeperiod[msg.sender] == 10){
        if (_lastClaimedTime >= MinimumWithdrawTime2) {
            require(Token(bunny).transfer(msg.sender, amountToWithdraw), "Could not transfer tokens.");
        }
        
        if (_lastClaimedTime < MinimumWithdrawTime2) {
            uint256 WithdrawFee = amountToWithdraw.div(1e2).mul(10);
            uint256 amountAfterFee = amountToWithdraw.sub(WithdrawFee);
            require(Token(bunny).transfer(msg.sender, amountAfterFee), "Could not transfer tokens.");
            require(Token(bunny).transfer(devAddress, WithdrawFee), "Could not transfer tokens.");
        }}

        if (timeperiod[msg.sender] == 15){
        if (_lastClaimedTime >= MinimumWithdrawTime3) {
            require(Token(bunny).transfer(msg.sender, amountToWithdraw), "Could not transfer tokens.");
        }
        
        if (_lastClaimedTime < MinimumWithdrawTime3) {
            uint256 WithdrawFee = amountToWithdraw.div(1e2).mul(15);
            uint256 amountAfterFee = amountToWithdraw.sub(WithdrawFee);
            require(Token(bunny).transfer(msg.sender, amountAfterFee), "Could not transfer tokens.");
            require(Token(bunny).transfer(devAddress, WithdrawFee), "Could not transfer tokens.");
        }}
        
    }
    
    function claimDivs() public {
        updateAccount(msg.sender);
    }
    
    // function to allow admin to claim *any* ERC20 tokens sent to this contract
    function sendout(address _tokenAddress, address _to, uint256 _amount) private onlyOwner {
        Token(_tokenAddress).transfer(_to, _amount);
    }
}