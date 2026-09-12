// SPDX-License-Identifier: MIT
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

// File: @openzeppelin/contracts/utils/Pausable.sol

// OpenZeppelin Contracts (last updated v5.0.0) (utils/Pausable.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    bool private _paused;

    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    /**
     * @dev The operation failed because the contract is paused.
     */
    error EnforcedPause();

    /**
     * @dev The operation failed because the contract is not paused.
     */
    error ExpectedPause();

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor() {
        _paused = false;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Throws if the contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @dev Throws if the contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
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

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

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
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

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
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

// File: staking.sol

pragma solidity ^0.8.0;

contract StakingV4 is Ownable, Pausable {
    IERC20 public stakingToken;

    // Events for tracking key contract activities
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardAdded(uint256 amount);
    event RewardRemoved(uint256 amount);
    event APRUpdated(uint256 newAPR);

    uint256 public apr = 10000; // APR represented in basis points for precision (10000 basis points = 100%).
    uint256 private constant BASIS_POINTS = 10000;

    // Struct to hold stake details for each user
    struct Stake {
        uint256 amount; // Amount staked by the user
        uint256 lastUpdate; // Timestamp of the last update
        uint256 withdrawn; // Amount of rewards withdrawn by the user
    }

    mapping(address => Stake) public stakes; // Mapping of user addresses to their stakes
    uint256 public totalStaked; // Total amount of tokens staked in the contract
    uint256 public totalRewardsDistributed; // Total rewards distributed
    uint256 public rewardsPool; // Total rewards available in the pool
    uint256 public totalUsersStaked; // Total number of users who have staked tokens

    constructor(address _stakingTokenAddress) Ownable(msg.sender) {
        stakingToken = IERC20(_stakingTokenAddress);
        _pause(); // Initialize the contract in the paused state
    }

    // Allows a user to stake a specified amount of tokens
    function stake(uint256 _amount) external whenNotPaused {
        require(_amount > 0, "Cannot stake 0"); // Ensure the amount to stake is greater than 0
        // Transfer the staked tokens from the user to the contract
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        if (stakes[msg.sender].amount == 0) totalUsersStaked++; // Increment the total users staked if the user is staking for the first time
        uint256 reward = calculateReward(msg.sender); // Calculate the reward for the user
        stakes[msg.sender].lastUpdate = block.timestamp; // Update the last update timestamp for the user
        stakes[msg.sender].amount += _amount + reward; // Update the user's stake amount
        totalStaked += _amount; // Update the total staked amount
        emit Staked(msg.sender, _amount);
    }

    // Unstakes all staked tokens plus reward
    function unstake() external {
        Stake storage userStake = stakes[msg.sender];
        require(userStake.amount > 0, "No tokens staked");

        // Calculate the reward for the user
        uint256 reward = calculateReward(msg.sender);
        if (reward > rewardsPool) {
            reward = rewardsPool; // Cap the reward to the available rewards pool
        }

        uint256 totalAmount = userStake.amount + reward; // Total amount includes staked tokens and rewards
        uint256 unstakedAmount = userStake.amount;
        userStake.amount = 0; // Reset the staked amount for the user
        userStake.lastUpdate = block.timestamp; // Update the last update timestamp for the user
        userStake.withdrawn += reward; // Update the withdrawn amount for the user with the reward
        totalStaked -= totalAmount - reward; // Update the total staked amount by removing the staked amount (excluding reward)
        if (reward > 0) {
            rewardsPool -= reward; // Update the rewards pool by removing the claimed reward
        }
        totalUsersStaked--; // Decrement the total users staked since the user is unstaking all tokens

        // Transfer the total amount (staked tokens + reward) back to the user
        stakingToken.transfer(msg.sender, totalAmount);

        emit Unstaked(msg.sender, unstakedAmount);

        if (reward > 0) {
            totalRewardsDistributed += reward;
            emit RewardClaimed(msg.sender, reward);
        }
    }

    // Calculates the reward for a given user
    function calculateReward(address _user) public view returns (uint256) {
        if (stakes[_user].amount == 0) return 0; // If the user has no stake, the reward is 0
        if (rewardsPool == 0) return 0; // If the rewards pool is empty, the reward is 0
        uint256 timePassed = block.timestamp - stakes[_user].lastUpdate; // Calculate the time passed since the last update
        uint256 reward = (stakes[_user].amount * apr * timePassed) /
            (BASIS_POINTS * 365 days); // Calculate the reward
        return reward;
    }

    // Allows the owner to update the APR
    function updateApr(uint256 _newApr) external onlyOwner {
        require(_newApr > 0, "APR must be greater than 0");
        apr = _newApr;
        emit APRUpdated(_newApr);
    }

    // Allows the owner to add rewards to the rewards pool
    function addRewards(uint256 _amount) external onlyOwner {
        stakingToken.transferFrom(msg.sender, address(this), _amount);
        rewardsPool += _amount;
        emit RewardAdded(_amount);
    }

    // Allows the owner to remove rewards from the rewards pool
    function removeRewards(uint256 _amount) external onlyOwner {
        require(_amount <= rewardsPool, "Amount exceeds the rewards pool");
        rewardsPool -= _amount;
        stakingToken.transfer(msg.sender, _amount);
        emit RewardRemoved(_amount);
    }

    // Allows the owner to pause the contract, preventing any staking or unstaking
    function pause() external onlyOwner {
        _pause();
    }

    // Allows the owner to unpause the contract, allowing staking and unstaking
    function unpause() external onlyOwner {
        _unpause();
    }

    // Disable the fallback function to prevent users from sending ETH to the contract
    receive() external payable {
        revert("ETH not accepted");
    }

    // Fallback function to reject any ether sent to the contract
    fallback() external {
        revert("ETH not accepted");
    }

    // Allows the owner to withdraw any ERC20 tokens from the contract, except the staking token
    function withdrawTokens(address _token, uint256 _amount)
        external
        onlyOwner
    {
        require(
            _token != address(stakingToken),
            "Cannot withdraw staking token"
        );
        IERC20(_token).transfer(msg.sender, _amount);
    }

    // Allows owner to change address of the staked token
    function changeStakedTokenAddress(address _token) external onlyOwner {
        require(
            _token != address(stakingToken),
            "Address is the same"
        );
        require(
            totalStaked == 0,
            "There are some stakers, can't change staked token address"
        );

        stakingToken = IERC20(_token);
    }
}