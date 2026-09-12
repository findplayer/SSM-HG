// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract MiningStakeContract {
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    address public owner;
    uint256 public maxUsers = 50;
    uint256 public STAKE_LIMIT = 500*10**18;
    
    struct Stake {
        uint256 amount;
        bool staked;
        uint256 reward;
    }

    mapping(address => Stake) public stakes;
    address[] public stakers;

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        owner = msg.sender;
    }

    function stake(uint256 _amount) external {
        require(stakes[msg.sender].staked == false, "You have already staked");
        require(_amount == STAKE_LIMIT, "Invalid staking amount");
        require(stakers.length < maxUsers, "Maximum number of users reached");

        stakingToken.transferFrom(msg.sender, address(this), _amount);
        stakes[msg.sender] = Stake(_amount, true, 0);
        stakers.push(msg.sender);
    }

    function unstake() external {
        require(stakes[msg.sender].staked, "You have not staked");

        stakingToken.transfer(msg.sender, stakes[msg.sender].amount);
        stakes[msg.sender].staked = false;
    }

    function distributeRewards(uint256 _rewardAmount) external {
        require(msg.sender == owner, "Only the owner can distribute rewards");
        require(rewardToken.transferFrom(msg.sender, address(this), _rewardAmount), "Transfer failed");
        uint256 rewardPerUser = _rewardAmount / stakers.length;
        for (uint i = 0; i < stakers.length; i++) {
            if (stakes[stakers[i]].staked) {
                stakes[stakers[i]].reward += rewardPerUser;
            }
        }
    }

    function claimReward() external {
        uint256 reward = stakes[msg.sender].reward;
        require(reward > 0, "No rewards to claim");
        stakes[msg.sender].reward = 0;
        rewardToken.transfer(msg.sender, reward);
    }

    function claimStuckTokens(address _token) external {
        require(msg.sender == owner, "Only the owner can claim stuck tokens");
        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner, amount);
    }

    function setMaxUsers(uint256 _maxUsers) external {
        require(msg.sender == owner, "Only the owner can set the maximum number of users");
        maxUsers = _maxUsers;
    }

    function setStakeLimit(uint256 _newLimit) external {
        require(msg.sender == owner, "Only the owner can set the maximum number of users");
        STAKE_LIMIT = _newLimit;
    }

    function setStakingToken(address _newStakingToken) external {
        require(msg.sender == owner, "Only the owner can update the staking token");
        stakingToken = IERC20(_newStakingToken);
    }

    function setRewardToken(address _newRewardToken) external {
        require(msg.sender == owner, "Only the owner can update the reward token");
        rewardToken = IERC20(_newRewardToken);
    }

    function getStakeInfo(address _user) external view returns (uint256 stakedAmount, bool isStaked, uint256 rewardAmount) {
        Stake storage stakeInfo = stakes[_user];
        return (stakeInfo.amount, stakeInfo.staked, stakeInfo.reward);
    }

    function getStakersCount() external view returns (uint256) {
        return stakers.length;
    }
}