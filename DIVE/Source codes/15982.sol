// Surrey Annabelle@moneyark.io
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract YieldDistribution {
    address public admin;
    IERC20 public stakingToken; 
    IERC20 public rewardToken; 

    struct Stake {
        uint256 amount;
        uint256 rewardDebt;
    }

  
    mapping(address => Stake) public stakers;
    
    uint256 public lastRewardTime;
    uint256 public accRewardPerShare;
    uint256 public rewardRate; 
    uint256 public constant PRECISION = 1e12; 

    event StakeAdded(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event StakeWithdrawn(address indexed user, uint256 amount);

    modifier onlyAdmin {
        require(msg.sender == admin, "Not an admin");
        _;
    }
    
    constructor(address _stakingToken, address _rewardToken, uint256 _rewardRate) {
        admin = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        lastRewardTime = block.timestamp;
    }


    function updatePool() public {
        if (block.timestamp <= lastRewardTime) {
            return;
        }
        uint256 stakingSupply = stakingToken.balanceOf(address(this));
        if (stakingSupply == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 multiplier = block.timestamp - lastRewardTime;
        uint256 reward = multiplier * rewardRate;
        accRewardPerShare += reward * PRECISION / stakingSupply;
        lastRewardTime = block.timestamp;
    }


    function stake(uint256 _amount) external {
        updatePool();
        Stake storage stake = stakers[msg.sender];
        
        if (stake.amount > 0) {
            uint256 pendingReward = stake.amount * accRewardPerShare / PRECISION - stake.rewardDebt;
            if (pendingReward > 0) {
                rewardToken.transfer(msg.sender, pendingReward);
                emit RewardClaimed(msg.sender, pendingReward);
            }
        }
        if (_amount > 0) {
            stakingToken.transferFrom(msg.sender, address(this), _amount);
            stake.amount += _amount;
            emit StakeAdded(msg.sender, _amount);
        }
        stake.rewardDebt = stake.amount * accRewardPerShare / PRECISION;
    }

    function pendingReward(address _user) external view returns (uint256) {
        Stake storage stake = stakers[_user];
        uint256 currentAccRewardPerShare = accRewardPerShare;
        uint256 stakingSupply = stakingToken.balanceOf(address(this));

        if (block.timestamp > lastRewardTime && stakingSupply != 0) {
            uint256 multiplier = block.timestamp - lastRewardTime;
            uint256 reward = multiplier * rewardRate;
            currentAccRewardPerShare += reward * PRECISION / stakingSupply;
        }

        return stake.amount * currentAccRewardPerShare / PRECISION - stake.rewardDebt;
    }


    function transferAdminship(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "New admin cannot be the zero address");
        admin = newAdmin;
    }

   
    function totalStaked() external view returns (uint256) {
        return stakingToken.balanceOf(address(this));
    }


    function recoverRewardTokens(address to, uint256 amount) external onlyAdmin {
        require(to != address(0), "Cannot recover to the zero address");
        require(amount > 0, "Amount must be greater than 0");
        uint256 contractBalance = rewardToken.balanceOf(address(this));
        require(amount <= contractBalance, "Cannot recover more than current balance");
        
        rewardToken.transfer(to, amount);
    }

 
    function updateStakingToken(address _newStakingToken) external onlyAdmin {
        require(_newStakingToken != address(0), "New staking token cannot be the zero address");
        require(address(stakingToken) != _newStakingToken, "New staking token must be different");
        stakingToken = IERC20(_newStakingToken);
    }

  
    function updateRewardToken(address _newRewardToken) external onlyAdmin {
        require(_newRewardToken != address(0), "New reward token cannot be the zero address");
        require(address(rewardToken) != _newRewardToken, "New reward token must be different");
        rewardToken = IERC20(_newRewardToken);
    }
}