// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts (last updated v4.9.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

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
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
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
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Returns true if the reentrancy guard is currently set to "entered", which indicates there is a
     * `nonReentrant` function in the call stack.
     */
    function _reentrancyGuardEntered() internal view returns (bool) {
        return _status == _ENTERED;
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// File: LNDRYstaking.sol


pragma solidity ^0.8.0;




contract LNDRYStaking is ReentrancyGuard, Ownable {
    IERC20 public lndryToken;

    struct Tier {
    uint256 minValue; // Minimum value to qualify for this tier
    uint256 maxValue; // Maximum value to qualify for this tier
    uint256 allocation; // Percent of weekly rewards
    uint256 totalStaked;
    }

    struct Stake {
        uint256 amount;
        uint256 tierIndex;
        uint256 stakeTime; // Time when tokens were staked
        uint256 lastUnstakeTime; // Last time an unstake was initiated for cooldown calculation
        bool unstakeInitiated;
        uint256 lastRewardActionTime;
        uint256 amountToUnstake;
        bool fastUnstake;
            uint256 unclaimedRewards; 
    }


    Tier[] public tiers;
    uint256 public weeklyRewardPool;
    uint256 public lastRewardUpdateTime;
    uint256 private constant PRECISION_FACTOR = 1e18;
address public feeCollector;


    uint256 public regularUnstakeCooldown = 7 days;
    uint256 public fastUnstakeCooldown = 1 days;
    uint256 public regularUnstakeFeePercentage = 100; // 1%
    uint256 public fastUnstakeFeePercentage = 500; // 5%

    mapping(address => Stake) public stakes; // Maps user address to their stake
    address[] private stakers; // List of all staker addresses for iteration
    event Staked(address indexed user, uint256 amount, uint256 tierIndex);
    event UnstakeInitiated(address indexed user, uint256 amount, bool fastUnstake);
    event Unstaked(address indexed user, uint256 amount, bool fastUnstake);
    event RewardClaimed(address indexed user, uint256 reward);
    event RewardsCompounded(address indexed user, uint256 amount);


constructor(address _lndryTokenAddress, address _initialOwner, address _feeCollector) Ownable(_initialOwner) {
    require(_feeCollector != address(0), "Invalid fee collector address");
    lndryToken = IERC20(_lndryTokenAddress);
    feeCollector = _feeCollector;
}

  function setRegularUnstakeCooldown(uint256 _cooldown) external onlyOwner {
        regularUnstakeCooldown = _cooldown;
    }

    function setFastUnstakeCooldown(uint256 _cooldown) external onlyOwner {
        fastUnstakeCooldown = _cooldown;
    }

    function setRegularUnstakeFeePercentage(uint256 _feePercentage) external onlyOwner {
        regularUnstakeFeePercentage = _feePercentage;
    }

    function setFastUnstakeFeePercentage(uint256 _feePercentage) external onlyOwner {
        fastUnstakeFeePercentage = _feePercentage;
    }

    function depositRewards(uint256 _amount, uint256[] calldata _allocations) external onlyOwner {
    require(_amount > 0, "Amount must be greater than 0");
    require(_allocations.length == tiers.length, "Allocations length must match tiers length");

    uint256 totalAllocation = 0;
    for (uint256 i = 0; i < _allocations.length; i++) {
        totalAllocation += _allocations[i];
    }
    require(totalAllocation == 100, "Total allocation must be 100%");
    
    // Before updating the weeklyRewardPool, calculate and update unclaimed rewards for each staker
    for(uint256 i = 0; i < stakers.length; i++) {
        address staker = stakers[i];
        uint256 pendingReward = calculateReward(staker); // Calculate current pending reward
        stakes[staker].unclaimedRewards += pendingReward - stakes[staker].unclaimedRewards; // Update unclaimed rewards
        stakes[staker].lastRewardActionTime = block.timestamp; // Update last action time to now
    }

    weeklyRewardPool += _amount; // Update the pool with the new amount
    require(lndryToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");

    lastRewardUpdateTime = block.timestamp; // Update the reward update time to now
}

   function emergencyTransferStakedTokens(address to) external onlyOwner nonReentrant {
        require(to != address(0), "Cannot transfer to the zero address");
        uint256 contractBalance = lndryToken.balanceOf(address(this));
        require(contractBalance > 0, "No tokens to transfer");
        
        require(lndryToken.transfer(to, contractBalance), "Token transfer failed");
        
    }
    function stake(uint256 _amount) external nonReentrant {
            require(_amount > 0, "Cannot stake 0 tokens");
            Stake storage userStake = stakes[msg.sender];
            userStake.amount += _amount;
            userStake.tierIndex = determineTier(userStake.amount);
            userStake.stakeTime = block.timestamp;
            userStake.lastUnstakeTime = block.timestamp; // Reset on new stake

            if (!isStaker(msg.sender)) {
                stakers.push(msg.sender);
            }
            recalculateTotalStaked();

            require(lndryToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
            emit Staked(msg.sender, _amount, userStake.tierIndex);
        }
function initiateUnstake(uint256 _amount, bool _fastUnstake) external {
    Stake storage userStake = stakes[msg.sender];
    require(_amount > 0 && _amount <= userStake.amount, "Invalid unstake amount");
    require(!userStake.unstakeInitiated, "Unstake already initiated");

    // Before initiating the unstake, reset unclaimed rewards to 0
    userStake.unclaimedRewards = 0;

    userStake.unstakeInitiated = true;
    userStake.amountToUnstake = _amount;
    userStake.fastUnstake = _fastUnstake;
    userStake.lastUnstakeTime = block.timestamp;

    emit UnstakeInitiated(msg.sender, _amount, _fastUnstake);
}
function setFeeCollector(address _feeCollector) external onlyOwner {
    require(_feeCollector != address(0), "Invalid address");
    feeCollector = _feeCollector;
}
   function completeUnstake() external nonReentrant {
    Stake storage userStake = stakes[msg.sender];
    require(userStake.unstakeInitiated, "Unstake not initiated");
    uint256 cooldown = userStake.fastUnstake ? fastUnstakeCooldown : regularUnstakeCooldown;
    require(block.timestamp >= userStake.lastUnstakeTime + cooldown, "Cooldown not met");

    uint256 feePercentage = userStake.fastUnstake ? fastUnstakeFeePercentage : regularUnstakeFeePercentage;
    uint256 fee = (userStake.amountToUnstake * feePercentage) / 10000;
    uint256 amountAfterFee = userStake.amountToUnstake - fee;

    userStake.amount -= userStake.amountToUnstake; // Deduct the unstaked amount
    userStake.unstakeInitiated = false; // Reset unstake state

    // Transfer the unstaked amount after fee to the user
    require(lndryToken.transfer(msg.sender, amountAfterFee), "Transfer failed");

    // Transfer the fee to the fee collector
    require(lndryToken.transfer(feeCollector, fee), "Fee transfer failed");

    emit Unstaked(msg.sender, userStake.amountToUnstake, userStake.fastUnstake);
}

function calculateReward(address _user) public view returns (uint256) {
    Stake memory userStake = stakes[_user];


    if (userStake.amount == 0 || tiers.length == 0) {
        return 0;
    }

    uint256 lastActionTime = (userStake.lastRewardActionTime == 0 || userStake.lastRewardActionTime < lastRewardUpdateTime) ? lastRewardUpdateTime : userStake.lastRewardActionTime;
    uint256 timeElapsed = block.timestamp > lastActionTime ? block.timestamp - lastActionTime : 0;

    if (timeElapsed > 7 days) {
        timeElapsed = 7 days;
    }

    // Adjusted calculation to ensure non-zero result for rewardPoolForElapsedPeriod
    uint256 rewardPoolForElapsedPeriod = (weeklyRewardPool * PRECISION_FACTOR * timeElapsed) / (7 days) / PRECISION_FACTOR;

    uint256 tierReward = rewardPoolForElapsedPeriod * tiers[userStake.tierIndex].allocation / 100;

    if (tiers[userStake.tierIndex].totalStaked == 0) {
        return 0; // Prevent division by zero
    }

    uint256 rewardPerShare = (tierReward * PRECISION_FACTOR) / tiers[userStake.tierIndex].totalStaked;

    uint256 pendingReward = (userStake.amount * rewardPerShare) / PRECISION_FACTOR;

    // Including unclaimed rewards in the total reward
    uint256 totalReward = pendingReward + userStake.unclaimedRewards;

    return totalReward;
}

function claimReward() external nonReentrant {
    uint256 reward = calculateReward(msg.sender);
    require(reward > 0, "No rewards to claim");

    require(lndryToken.transfer(msg.sender, reward), "Transfer failed");
    Stake storage userStake = stakes[msg.sender];
    userStake.lastRewardActionTime = block.timestamp;
    userStake.unclaimedRewards = 0; // Reset unclaimed rewards to 0

    emit RewardClaimed(msg.sender, reward);
}

function getUnstakeCooldownLeft(address _user) public view returns (uint256 timeLeft, bool isFastUnstake) {
    Stake memory userStake = stakes[_user];
    if (!userStake.unstakeInitiated) {
        return (0, false); // No unstake initiated, so no cooldown
    }

    uint256 cooldownEnd;
    if (userStake.fastUnstake) {
        cooldownEnd = userStake.lastUnstakeTime + fastUnstakeCooldown;
    } else {
        cooldownEnd = userStake.lastUnstakeTime + regularUnstakeCooldown;
    }

    if (block.timestamp >= cooldownEnd) {
        return (0, userStake.fastUnstake); // Cooldown completed
    }

    return (cooldownEnd - block.timestamp, userStake.fastUnstake); // Time left and type of unstake
}
 function addTier(uint256 _minValue, uint256 _maxValue, uint256 _allocation) external onlyOwner {
    require(_minValue < _maxValue, "minValue must be less than maxValue");
    Tier memory newTier = Tier({
        minValue: _minValue,
        maxValue: _maxValue,
        allocation: _allocation,
        totalStaked: 0
    });

    // Find the correct position to insert the new tier
    uint256 position = tiers.length;
    for (uint256 i = 0; i < tiers.length; i++) {
        if (_minValue < tiers[i].minValue) {
            position = i;
            break;
        }
    }

    // Shift tiers and insert the new tier
    tiers.push(newTier); // Add at the end to increase the array size
    for (uint256 i = tiers.length - 1; i > position; i--) {
        tiers[i] = tiers[i - 1];
    }
    tiers[position] = newTier;
}
   function removeTier(uint256 index) external onlyOwner {
    require(index < tiers.length, "Invalid tier index");

    for (uint256 i = index; i < tiers.length - 1; i++) {
        tiers[i] = tiers[i + 1];
    }
    tiers.pop(); // Remove the last element after shifting
}

 
function recalculateAllStakes() internal {
    for (uint256 i = 0; i < stakers.length; i++) {
        address staker = stakers[i];
        Stake storage userStake = stakes[staker];
        uint256 newTierIndex = determineTier(userStake.amount);
        if (newTierIndex != userStake.tierIndex) {
            userStake.tierIndex = newTierIndex;
            // Adjust any additional logic based on the new tier assignment
        }
    }
recalculateTotalStaked();
}
    function determineTier(uint256 amount) internal view returns (uint256) {
    for (uint256 i = 0; i < tiers.length; i++) {
        if (amount >= tiers[i].minValue && amount <= tiers[i].maxValue) {
            return i;
        }
    }
    revert("Amount does not qualify for any tier");
}

        function recalculateTotalStaked() internal {
        for (uint256 i = 0; i < tiers.length; i++) {
            tiers[i].totalStaked = 0;
        }

        for (uint256 i = 0; i < stakers.length; i++) {
            address stakerAddress = stakers[i];
            Stake memory userStake = stakes[stakerAddress];
            uint256 tierIndex = userStake.tierIndex;
            tiers[tierIndex].totalStaked += userStake.amount;
        }
    }  
    
    
    function isStaker(address _address) internal view returns (bool) {
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i] == _address) {
                return true;
            }
        }
        return false;
    }
    function removeStaker(address staker) internal {
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i] == staker) {
                stakers[i] = stakers[stakers.length - 1];
                stakers.pop();
                return;
            }
        }
    }

    function compoundRewards() external nonReentrant {
    uint256 reward = calculateReward(msg.sender);
    require(reward > 0, "No rewards to compound");

    Stake storage userStake = stakes[msg.sender];
    userStake.amount += reward; // Add rewards to the staked amount

    // Recalculate the user's tier based on the new staked amount
    uint256 newTierIndex = determineTier(userStake.amount);
    if (newTierIndex != userStake.tierIndex) {
        userStake.tierIndex = newTierIndex; // Update the user's tier if it has changed
    }

    recalculateTotalStaked(); // Recalculate the total staked amount in each tier, if necessary
     userStake.unclaimedRewards = 0; // Reset unclaimed rewards to 0
    userStake.lastRewardActionTime = block.timestamp;
    emit RewardsCompounded(msg.sender, reward);
}

 function getNumberOfStakers() public view returns (uint256) {
        return stakers.length;
    }

    function getTotalAmountStaked() public view returns (uint256 totalStaked) {
        for (uint256 i = 0; i < stakers.length; i++) {
            address stakerAddress = stakers[i];
            totalStaked += stakes[stakerAddress].amount;
        }
    }
    function getTierAPY(uint256 tierIndex) public view returns (uint256) {
    require(tierIndex < tiers.length, "Invalid tier index");

    uint256 rewardsPerWeek = weeklyRewardPool * tiers[tierIndex].allocation / 100;
    uint256 totalStakedInTier = tiers[tierIndex].totalStaked;

    // Calculate APY for the tier based on rewards earned and total staked amount
    if (totalStakedInTier == 0) {
        return 0; // Avoid division by zero
    }
    return (rewardsPerWeek * 52 * 100) / totalStakedInTier; // Multiply by 52 for annualization
}
  function getUserAPY(address user) public view returns (uint256) {
        Stake memory userStake = stakes[user];
        // Ensure the user has an existing stake
        if (userStake.amount == 0) {
            return 0; // User has no stake, thus APY is 0
        }
        // Determine the user's tier based on their current stake
        uint256 tierIndex = userStake.tierIndex;
        // Fetch and return the APY for the determined tier
        return getTierAPY(tierIndex);
    }

}