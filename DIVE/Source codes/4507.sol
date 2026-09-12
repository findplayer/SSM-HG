// Surrey Annabelle@moneyark.io
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
    
interface IERC20 {
        function totalSupply() external view returns (uint256);
        function balanceOf(address account) external view returns (uint256);
        function transfer(address recipient, uint256 amount) external returns (bool);
        function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    }
contract DynamicMiningPowerAdjustment {
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
    uint256 public totalStaked;
    uint256 public constant PRECISION = 1e12;
    uint256 public adjustmentFactor;

    event StakeAdded(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    event StakeWithdrawn(address indexed user, uint256 amount);

    modifier onlyAdmin {
        require(msg.sender == admin, "Not an admin");
        _;
    }
    
    constructor(address _stakingToken, address _rewardToken, uint256 _rewardRate, uint256 _adjustmentFactor) {
        admin = msg.sender;
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        lastRewardTime = block.timestamp;
        adjustmentFactor = _adjustmentFactor; //This factor determines how aggressively the reward rate adjusts.
    }

    function updatePool() public {
        if (block.timestamp <= lastRewardTime) {
            return;
        }
        if (totalStaked == 0) {
            lastRewardTime = block.timestamp;
            return;
        }
        
        uint256 multiplier = block.timestamp - lastRewardTime;
        uint256 reward     = multiplier * rewardRate;
        accRewardPerShare += reward * PRECISION / totalStaked;
        lastRewardTime = block.timestamp;
        adjustRewardRate();
    }

    function adjustRewardRate() internal {
        uint256 baseRewardRate = 1 ether;
        uint256 totalStakedThreshold1 = 500 * 10**18;
        uint256 totalStakedThreshold2 = 1000 * 10**18;
        if (totalStaked > totalStakedThreshold2) {
            rewardRate = baseRewardRate + adjustmentFactor;
        } else if (totalStaked < totalStakedThreshold1) {
            rewardRate = baseRewardRate - adjustmentFactor;
            if (rewardRate < baseRewardRate / 2) {
                rewardRate = baseRewardRate / 2;
            }
        }
    }

    function stake(uint256 _amount) external {
        updatePool();
        Stake storage stake = stakers[msg.sender];
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        totalStaked += _amount;
        stake.amount += _amount;
        stake.rewardDebt = stake.amount * accRewardPerShare / PRECISION;
        emit StakeAdded(msg.sender, _amount);
    }

    function withdraw(uint256 _amount) external {
        Stake storage stake = stakers[msg.sender];
        require(stake.amount >= _amount, "withdraw: not good");
        updatePool();
        uint256 pending = (stake.amount * accRewardPerShare / PRECISION) - stake.rewardDebt;
        if(pending > 0) {
            rewardToken.transfer(msg.sender, pending);
        }
        stake.amount -= _amount;
        totalStaked -= _amount;
        stakingToken.transfer(msg.sender, _amount);
        stake.rewardDebt = stake.amount * accRewardPerShare / PRECISION;
        emit StakeWithdrawn(msg.sender, _amount);
    }

    function claimReward() external {
        Stake storage stake = stakers[msg.sender];
        updatePool();
        uint256 pending = (stake.amount * accRewardPerShare / PRECISION) - stake.rewardDebt;
        if(pending > 0) {
            rewardToken.transfer(msg.sender, pending);
            stake.rewardDebt = stake.amount * accRewardPerShare / PRECISION;
            emit RewardClaimed(msg.sender, pending);
        }
    }

    function setRewardRate(uint256 _rewardRate) external onlyAdmin {
        rewardRate = _rewardRate;
    }

    function setAdjustmentFactor(uint256 _adjustmentFactor) external onlyAdmin {
        adjustmentFactor = _adjustmentFactor;
    }
}