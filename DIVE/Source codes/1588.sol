// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
   
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}



library SafeMath {
    
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }
    
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }
    
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }
    
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }
    
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }


    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }


    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }


    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }
    
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }
    
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }
    
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

contract Rome {
    using SafeMath for uint256;
    string public name = "Vestmap Rome";
    IERC20 public  stakeToken;
    uint256 startDate;
    IERC20 public  rewardToken;
    uint public  totalPool;
    uint public  minstakeAmount;
     uint public  maxstakeAmount;
    bool public poolStatus;
    //declaring owner state variable
    address public owner;
    //declaring default APY (default 0.1% daily or 36.5% APY yearly)
    uint256 public defaultAPY = 24;
    uint256 public constant LOCK_PERIOD = 1104 hours;
     struct UserInfo {    
        uint256 stakeTime;
        uint256 amount;
    }

    //declaring total staked
    uint256 public totalStaked;
    //users staking balance
    mapping(address => uint256) public stakingBalance;
    //mapping list of users who ever staked
    mapping(address => bool) public hasStaked;
    //mapping list of users who are staking at the moment
    mapping(address => bool) public isStakingAtm;
     //array of all stakers
    address[] public stakers;
    mapping(address => UserInfo[]) public userInfo;
    
    constructor(IERC20  _stakeToken, IERC20 _rewardToken , uint _totalPool, bool  _poolStatus, uint _minstakeAmount, uint _maxstakeAmount)  payable {
        stakeToken = _stakeToken;
        startDate = block.timestamp;
        rewardToken = _rewardToken;
        totalPool = _totalPool * (10**18);
        poolStatus = _poolStatus;
        minstakeAmount = _minstakeAmount * (10**18);
        maxstakeAmount = _maxstakeAmount * (10**18);
        owner = msg.sender;
    }
     function changeTotalpool(uint256 _value) public {
        //only owner can issue airdrop
        require(msg.sender == owner, "Only contract creator can change Total pool");
        require(
            _value > 0,
            "Pool value has to be more than 0, try 100 for (0.100% daily) instead"
        );
        totalPool = _value * (10**18);
    }
     function changepoolStatus(bool _value) public {
        //only owner can issue airdrop
        require(msg.sender == owner, "Only contract creator can change Pool Status");
        poolStatus = _value;
    }
   
    //stake tokens function
     error InvalidAmount (uint256 totalreward,uint256 mins,uint256 rew);
     error Notstaked (string warning);
    
    function stakeTokens(uint256 _amount) public {        
        //must be more than 0
       require(_amount > 0, "amount cannot be 0");
       totalStaked = totalStaked + _amount;
       if(totalStaked>totalPool) {
            revert Notstaked({
                warning: "Warning! Pool limit is reached."
            }); 
        }
        if(minstakeAmount > _amount) {
           revert Notstaked({
                warning: "Warning! Your stake amount is lower than minimum stake amount"
            }); 
        }
        if(maxstakeAmount < _amount) {
           revert Notstaked({
                warning: "Warning! Your stake amount is bigger than maximum stake amount"
            }); 
        }
         if(poolStatus == false) {
                revert Notstaked({
                warning: "Warning! Pool status is closed."
            }); 
        }
        stakeToken.transferFrom(msg.sender, address(this), _amount);        
        stakingBalance[msg.sender] = stakingBalance[msg.sender] + _amount;
        userInfo[msg.sender].push(
            UserInfo(                
                block.timestamp,               
                 _amount
            )
        );
        //checking if user staked before or not, if NOT staked adding to array of stakers
        if (!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
        }
     
    }
    //unstake tokens function
    function stakeCheck(address wallet) public view returns(uint256) {
        if(userInfo[wallet].length>0) {
            return 1;
        }
        else 
        {
           return 0;
        }
    }
        function timeCheck() public view returns(uint256) {
        if( startDate + LOCK_PERIOD <=   block.timestamp) {
            return 1;
        }
        else 
        {
           return 0;
        }
    }
    function unstakeTokens() public {
        require(userInfo[msg.sender].length>0," You don't have any stakes yet.");

        for (uint256 i = 0; i < userInfo[msg.sender].length; i++) {
        uint256 mins =0;
        require(startDate + LOCK_PERIOD <=   block.timestamp, " Too early to unstake");   
                uint256 balance = stakingBalance[msg.sender];
        uint256 divisor = 100000;   
        if (block.timestamp >= userInfo[msg.sender][i].stakeTime + LOCK_PERIOD) {
                    
                mins = (((startDate  + LOCK_PERIOD) - userInfo[msg.sender][i].stakeTime  )/60);
         
            }
        else {
            if ( userInfo[msg.sender][i].stakeTime>(startDate  + LOCK_PERIOD)) {
             mins = 0;
            }
      else {    
          mins = ((block.timestamp-userInfo[msg.sender][i].stakeTime)/60);     
             }   
         }
        uint256 hoursmultiplier = 365*24*60;
        uint256 custommultiplier = defaultAPY*divisor;
        uint256 totalreward = SafeMath.div(custommultiplier,hoursmultiplier);        
        uint256 reward = (balance/100)*totalreward;
       
        uint256 rew = SafeMath.div(reward,divisor)*mins;       
        totalStaked = totalStaked - balance;
        stakeToken.transfer(msg.sender, balance);
        rewardToken.transfer(msg.sender, rew);
        delete userInfo[msg.sender];
        //reseting users staking balance
        stakingBalance[msg.sender] = 0;
        //updating staking status
        isStakingAtm[msg.sender] = false;

        }
    }
    function gstartDate() public view returns(uint256) {
        return startDate;
    }
     function userRewards() public view returns(uint256) {
        uint256 totalrewards=0;
      for (uint256 i = 0; i < userInfo[msg.sender].length; i++) {
        uint256 mins =0;
        uint256 balance = stakingBalance[msg.sender];
        uint256 divisor = 100000;
        if (block.timestamp >= userInfo[msg.sender][i].stakeTime + LOCK_PERIOD) {
           
                
                mins = (((startDate  + LOCK_PERIOD) - userInfo[msg.sender][i].stakeTime  )/60);
          
            }
        else {
             if ( userInfo[msg.sender][i].stakeTime>(startDate  + LOCK_PERIOD)) {
             mins = 0;
            }
         else {
          mins = ((block.timestamp-userInfo[msg.sender][i].stakeTime)/60);        
            }
               
         }       
        uint256 hoursmultiplier = 365*24*60;
        uint256 custommultiplier = defaultAPY*divisor;
        uint256 totalreward = SafeMath.div(custommultiplier,hoursmultiplier);        
        uint256 reward = (balance/100)*totalreward;
        uint256 rew = SafeMath.div(reward,divisor)*mins;
        totalrewards += rew;
      }
       return totalrewards;
     }
    //change APY value for custom staking
    function changeAPY(uint256 _value) public {
        //only owner can issue airdrop
        require(msg.sender == owner, "Only contract creator can change APY");
        require(
            _value > 0,
            "APY value has to be more than 0, try 100 for (0.100% daily) instead"
        );
        defaultAPY = _value;
    }

}