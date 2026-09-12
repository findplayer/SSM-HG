// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

interface ITellorOracle {
    function depositStake(uint256 _amount) external;
    function submitValue(
        bytes32 _queryId,
        bytes calldata _value,
        uint256 _nonce,
        bytes calldata _queryData
    ) external;
    function requestStakingWithdraw(uint256 _amount) external;
    function withdrawStake() external;
    function getTimeOfLastNewValue() external view returns (uint256);
}

interface ITellorFlex {
    function mintToOracle() external;
    function approve(address _spender, uint256 _amount) external;
    function transfer(address _recipient, uint256 _amount) external returns (bool);
    function balanceOf(address _account) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract TellorMagic {
    struct Stake {
        uint256 stakedAmount;
        uint256 rewards;
        uint256 lockedAmount;
        uint256 lockedTimestamp;
    }

    address public owner;
    address public marketingWallet;

    ITellorOracle public tellorOracle = ITellorOracle(0x8cFc184c877154a8F9ffE0fe75649dbe5e2DBEbf);
    ITellorFlex public tellorFlex = ITellorFlex(0x88dF592F8eb5D7Bd38bFeF7dEb0fBc02cf3778a0);

    // ITellorOracle public tellorOracle = ITellorOracle(0xB0ff935b775a70504b810cf97c39987058e18550); // polygon mumbai
    // ITellorFlex public tellorFlex = ITellorFlex(0x3251838bd813fdf6a97D32781e011cce8D225d59); // polygon mumbai
    
    mapping(address => Stake) public userStakes;
    mapping(address => uint256) private rewardIndexOf;
    
    uint256 private rewardIndex;

    uint256 public totalStakedAmount;
    uint256 public MIN_STAKE_AMOUNT = 1e18; // 1 TRB
    uint256 public managementFee = 1_000; // 10%

    uint256 private constant MULTIPLIER = 1e18;
    uint256 private constant MANAGEMENT_FEE_CAP = 3_000; // Management fee should not exceed 30%.

    bool public stakePaused;

    event Staked(address indexed user, uint256 amount);
    event WithdrawRequested(address indexed user, uint256 amount);
    event Withdrawed(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can call this function");
        _;
    }

    modifier whenStakeNotPaused() {
        require(!stakePaused, "Stake is paused");
        _;
    }

    constructor(address _marketingWallet) {
        owner = msg.sender;
        marketingWallet = _marketingWallet;
    }

    function _updateRewardIndex() internal {
        uint256 currentTotalRewards = tellorFlex.balanceOf(address(this));
        if (currentTotalRewards == 0 || totalStakedAmount == 0) return;

        rewardIndex += (currentTotalRewards * MULTIPLIER) / totalStakedAmount;
    }


    function _calculateRewards(address account)
        private
        view
        returns (uint256)
    {
        uint256 shares = userStakes[account].stakedAmount;
        return (shares * (rewardIndex - rewardIndexOf[account])) / MULTIPLIER;
    }

    function calculateRewardsEarned(address account)
        external
        view
        returns (uint256)
    {
        return userStakes[account].rewards + _calculateRewards(account);
    }


    function _updateRewards(address account) private {
        uint256 rewards = _calculateRewards(account);
        uint256 fee = rewards * managementFee / 10_000;

        userStakes[account].rewards += (rewards - fee);
        userStakes[marketingWallet].rewards += fee;

        rewardIndexOf[account] = rewardIndex;
    }


    // Deposit and stake
    function depositAndStake(uint256 _amount) external whenStakeNotPaused {
        require(_amount >= MIN_STAKE_AMOUNT, "Not enough staking amount");
        
        // Update rewards
        _updateRewards(msg.sender);

        // Transfer TRB to this contract
        tellorFlex.transferFrom(msg.sender, address(this), _amount);

        // Update stake data
        Stake storage _stake = userStakes[msg.sender];
        _stake.stakedAmount += _amount;

        // Increase total staked amount
        totalStakedAmount += _amount;

        // stake into Tellor Oracle contract
        tellorFlex.approve(address(tellorOracle), _amount);
        tellorOracle.depositStake(_amount);

        emit Staked(msg.sender, _amount);
    }

    /// @dev This function requests withdraw unstake to tellor oracle contract
    /// There is 7 days of locking time to withdraw from tellor oracle contract
    function requestStakingWithdraw(uint256 _amount) external {
        Stake storage _stake = userStakes[msg.sender];
        require(_stake.stakedAmount >= _amount, "Insufficient staked amount");

        // Update rewards
        _updateRewards(msg.sender);

        // Update locked data
        _stake.lockedAmount += _amount;
        _stake.lockedTimestamp = block.timestamp;
        _stake.stakedAmount -= _amount;

        totalStakedAmount -= _amount;

        // Request staking to tellor oracle contract
        tellorOracle.requestStakingWithdraw(_amount);

        emit WithdrawRequested(msg.sender, _amount);
    }

    /// @notice Withdraw from tellor oracle.
    function withdrawStake() external {
        Stake storage _stake = userStakes[msg.sender];

        // 7 days limitation comes from tellor oracle contract. :)
        require(_stake.lockedTimestamp + 7 days < block.timestamp, "7 days is not passed yet");

        // withdraw from oracle
        tellorOracle.withdrawStake();

        tellorFlex.transfer(msg.sender, _stake.lockedAmount);

        emit Withdrawed(msg.sender, _stake.lockedAmount);

        // Update staking data
        _stake.lockedAmount = 0;
        _stake.lockedTimestamp = 0;
    }

    function claimRewards() external {
        _updateRewards(msg.sender);

        Stake storage _stake = userStakes[msg.sender];

        uint256 balance = tellorFlex.balanceOf(address(this));
        tellorFlex.transfer(msg.sender,  balance >_stake.rewards ? _stake.rewards : balance);
        
        emit RewardClaimed(msg.sender, _stake.rewards);

        _stake.rewards = 0;

    }

    /// @notice Submit data to Tellor Oracle contract
    function submitValue(
        bytes32 _queryId,
        bytes calldata _value,
        uint256 _nonce,
        bytes calldata _queryData
    ) external onlyOwner {
        require(block.timestamp - tellorOracle.getTimeOfLastNewValue() > 60, "too few reward");
        tellorOracle.submitValue(_queryId, _value, _nonce, _queryData);

        _updateRewardIndex();
    }

    function mintToOracle() external onlyOwner {
        tellorFlex.mintToOracle();
    }

    function approve(address _spender, uint256 _amount) external onlyOwner {
        tellorFlex.approve(_spender, _amount);
    }

    // Admin Set Actions
    function setTellorOracle(address _tellorOracle) external onlyOwner {
        tellorOracle = ITellorOracle(_tellorOracle);
    }

    function setTellorFlex(address _tellorFlex) external onlyOwner {
        tellorFlex = ITellorFlex(_tellorFlex);
    }

    function togglePause() external onlyOwner {
        stakePaused = !stakePaused;
    }

    function setMinStakeAmount(uint256 _amount) external onlyOwner {
        MIN_STAKE_AMOUNT = _amount;
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid owner");
        owner = _newOwner;
    }

    function setManagementFee(uint256 _fee) external onlyOwner {
        require(_fee <= MANAGEMENT_FEE_CAP, "Too high");
        managementFee = _fee;
    }

    function setMarketingWallet(address _account) external onlyOwner {
        require(_account != address(0), "Invalid marketing wallet");
        marketingWallet = _account;
    }
}