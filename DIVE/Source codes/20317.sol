/**
 *Submitted for verification at Etherscan.io on 2024-03-11
*/

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;


interface IERC20 {
    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract ORB3Staking {
    IERC20 public stakingToken;
    address public owner;
    uint256 public dailyROI;
    address public feeAddress;
    uint256 public feeBPS;
    uint256 public totalStaked;

    struct StakerInfo {
        uint256 stakedAmount;
        uint256 stakingStartTime;
        uint256 lastClaimTime;
        uint256 rewards;
        uint256 vestingPeriod; // User-selected vesting period in seconds
    }

    mapping(address => StakerInfo) public stakers;

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 timestamp,
        uint256 vestingPeriod
    );
    event Unstaked(address indexed user, uint256 amount, uint256 timestamp);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRate);

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    constructor(address _stakingToken, address _feeAddress, uint256 _feeBPS) {
        stakingToken = IERC20(_stakingToken);
        owner = msg.sender; // Set the deployer as the owner
        feeAddress = _feeAddress;
        feeBPS = _feeBPS;
    }

    function stake(uint256 _amount, uint256 _vestingPeriod) external {
        require(_amount > 0, "Cannot stake 0 tokens");
        require(
            _vestingPeriod == 30 days ||
                _vestingPeriod == 60 days ||
                _vestingPeriod == 90 days ||
                _vestingPeriod == 120 days,
            "Invalid vesting period"
        );
        uint256 feeAmount = _amount * feeBPS / 10000;
        require(stakingToken.transferFrom(msg.sender, address(this), _amount),'stake failed');
        stakingToken.transfer(feeAddress, feeAmount);
        StakerInfo storage staker = stakers[msg.sender];
        updateReward(msg.sender); // Update rewards before changing staked amount

        staker.stakedAmount += _amount - feeAmount;
        totalStaked += _amount - feeAmount;
        staker.stakingStartTime = block.timestamp;
        staker.lastClaimTime = block.timestamp; // Reset last claim time on new stake
        staker.vestingPeriod = _vestingPeriod; // Set the user-selected vesting period

        emit Staked(msg.sender, _amount, block.timestamp, _vestingPeriod);
    }

    function setDailyROI(uint256 _dailyROI) external onlyOwner {
        require(_dailyROI <= 10000, "ROI too high"); // Ensuring the ROI doesn't exceed 100%
        dailyROI = _dailyROI;
    }

    function setFeeBPS(uint256 _feeBPS) external onlyOwner {
        require(_feeBPS <= 10000, "fee failed"); // Ensuring the fee doesn't exceed 100%
        feeBPS = _feeBPS;
    }

    function unstake(uint256 _amount) external {
        StakerInfo storage staker = stakers[msg.sender];
        require(
            block.timestamp >= staker.stakingStartTime + staker.vestingPeriod,
            "Tokens are still in vesting period"
        );
        require(
            staker.stakedAmount >= _amount,
            "Not enough balance to unstake"
        );

        updateReward(msg.sender); // Update rewards before unstaking

        staker.stakedAmount -= _amount;
        totalStaked -= _amount;

        require(stakingToken.transfer(msg.sender, _amount), "Unstake failed");

        emit Unstaked(msg.sender, _amount, block.timestamp);
    }

    function claimReward() external {
        updateReward(msg.sender);

        uint256 reward = stakers[msg.sender].rewards;
        require(reward > 0, "No reward available");

        stakers[msg.sender].rewards = 0;
        require(
            stakingToken.transfer(msg.sender, reward),
            "Reward transfer failed"
        );

        emit RewardPaid(msg.sender, reward);
    }

    function updateReward(address account) internal {
        StakerInfo storage staker = stakers[account];
        if (staker.stakedAmount > 0) {
            uint256 timeSinceLastClaim = block.timestamp - staker.lastClaimTime;
            uint256 reward = (timeSinceLastClaim * staker.stakedAmount * dailyROI) / (10000 * 86400); 
            staker.rewards += reward;
            staker.lastClaimTime = block.timestamp;
        }
    }

    function earned(address account) public view returns (uint256) {
        StakerInfo storage staker = stakers[account];
        uint256 timeSinceLastClaim = block.timestamp - staker.lastClaimTime;
        uint256 currentReward = (timeSinceLastClaim * staker.stakedAmount * dailyROI) / (10000 * 86400); // Convert daily ROI to per second ROI
        return staker.rewards + currentReward;
    }
  
}