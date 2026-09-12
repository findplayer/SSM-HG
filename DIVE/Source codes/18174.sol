// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract DynamicPowerPool {
    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
        uint256 lastUpdateTime;
    }
    mapping(address => Staker) public stakers;
    uint256 public totalStaked;
    uint256 public networkMiningPower = 100;
    uint256 public rewardRate = 1 ether;
    address public owner;
    IERC20 public stakingToken;
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event MiningPowerUpdated(uint256 newPower);

    constructor(address _stakingToken) {
        owner = msg.sender;
        stakingToken = IERC20(_stakingToken);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    function stake(uint256 _amount) external {
        totalStaked += _amount;
        Staker storage staker = stakers[msg.sender];
        staker.amountStaked += _amount;
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function calculateReward(address stakerAddress) public view returns (uint256) {
        Staker storage staker = stakers[stakerAddress];
        uint256 reward = (staker.amountStaked * networkMiningPower * rewardRate) / 1 ether;
        return reward - staker.rewardDebt;
    }

    function updateNetworkMiningPower(uint256 _newPower) external onlyOwner {
        networkMiningPower = _newPower;
        emit MiningPowerUpdated(_newPower);
    }

    function claimReward() external {
        Staker storage staker = stakers[msg.sender];
        uint256 reward = calculateReward(msg.sender);
        staker.rewardDebt += reward;
        stakingToken.transfer(msg.sender, reward);
        emit RewardPaid(msg.sender, reward);
    }

    function withdraw(uint256 _amount) external {
        Staker storage staker = stakers[msg.sender];
        uint256 reward = calculateReward(msg.sender);
        staker.amountStaked -= _amount;
        staker.rewardDebt += reward;
        stakingToken.transfer(msg.sender, _amount + reward);
        emit Withdrawn(msg.sender, _amount);
        emit RewardPaid(msg.sender, reward);
    }

    function updateStakerSnapshot(address stakerAddress) internal {
        Staker storage staker = stakers[stakerAddress];
        staker.lastUpdateTime = block.timestamp;
    }

   
}