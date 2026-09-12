/*
MicroStaking
Staking Live
WEBSITE:   https://microstaking.co
TELEGRAM:  https://t.me/MicroStaking_Portal2024	
TWITTER:   https://twitter.com/MicroStaking
GITDOC:    https://docs.microstaking.co/
*/


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

// File: staking.sol

/*
MicroStaking
Staking Live
WEBSITE:   https://microstaking.co
TELEGRAM:  https://t.me/MicroStaking_Portal2024	
TWITTER:   https://twitter.com/MicroStaking
GITDOC:    https://docs.microstaking.co/
*/

pragma solidity ^0.8.20;



contract MSStake is Ownable {
    event e_Stake(uint256 value, address from);
    event e_ClaimReward(uint256 value, address from);
    event e_Withdraw(uint256 value, address to);

    error UnauthorizedOracleAccount(address account);
    error UnauthorizedWithdrawAccount(address account);
    error WithdrawAccountIsNotSet();

    // Token for rewards
    struct RewardInfo {
        address rewardTokenAddress;
        uint16 rewardPercent;
        uint256 rewardPerDay;
        uint256 rewardBalance; // balance for reward: update when initialize and user claim
        uint256 totalStakeBalance; // update when user stake and withdraw
    }

    RewardInfo public rInfo = RewardInfo(address(0), 30, 0, 0, 0);

    struct RewardsConfig {
        uint256 startAt;
        uint256 endAt;
    }

    RewardsConfig public rCfg =
        RewardsConfig(
            _getTodayZero(block.timestamp),
            _getTodayZero(block.timestamp) + 365 days
        );

    constructor(address rewardToken) Ownable(msg.sender) {
        require(rewardToken != address(0), "Invalid reward token address");
        rInfo.rewardTokenAddress = rewardToken;
        require(
            IERC20(rInfo.rewardTokenAddress).totalSupply() > 0,
            "Invalid reward token supply"
        );
    }

    function initialize() external onlyOwner {
        require(rInfo.rewardPerDay == 0, "rInfo.rewardPerDay is already set");
        require(
            IERC20(rInfo.rewardTokenAddress).balanceOf(msg.sender) >=
                (IERC20(rInfo.rewardTokenAddress).totalSupply() *
                    rInfo.rewardPercent) /
                    100,
            "Invalid reward token balance"
        );
        safeTransferFrom(
            rInfo.rewardTokenAddress,
            msg.sender,
            address(this),
            (IERC20(rInfo.rewardTokenAddress).totalSupply() *
                rInfo.rewardPercent) / 100
        );
        rInfo.rewardBalance = balanceOfRewardToken();
        rInfo.rewardPerDay = rInfo.rewardBalance / 365;
        WithdrawAccount = msg.sender;
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "ERC20: TRANSFER_FROM_FAILED"
        );
    }

    // Stake will be closed after 365 days(including deploy's day)
    struct UserStakeByDay {
        uint256 stake;
        uint256 unstake;
    }

    struct StakeByDay {
        uint256 totalStakeAmount; // totalStakeAmount for the day
        uint256 totalUnstakeAmount; // totalUnstakeAmount for the day
        mapping(address => UserStakeByDay) userStakeByDay;
    }

    mapping(uint16 => StakeByDay) public userStakeMap;

    struct StakeInfo {
        uint256 userTotalStakeAmount;
        uint256 userRewarded;
        uint256 userRewardedByDay;
    }

    mapping(address => StakeInfo) public userTotalStakeMap;

    address public WithdrawAccount = address(0);

    // Reward part
    // ClaimRewards:
    // calculate reward amount by day
    function ClaimRewards() external returns (bool) {
        require(rInfo.rewardPerDay > 0, "rInfo.rewardPerDay is not set");
        require(
            _gapDays(block.timestamp, rCfg.startAt) >= 5,
            "Claim Opens at day 5"
        );
        // require(rInfo.totalStakeBalance > 0, "No stakes");
        (uint256 amount, uint256 gap) = CalculateReward();
        require(
            balanceOfRewardToken() - amount > 0,
            "Insufficient reward balance"
        );
        if (amount == 0) {
            return false;
        }
        userTotalStakeMap[msg.sender].userRewarded += amount;
        userTotalStakeMap[msg.sender].userRewardedByDay = gap;

        _claimRewards(amount);

        return true;
    }

    // deposit at day 0, reward at day 1
    // day[i]'s reward = Σ(user's stakes to day[i-1] - unstaked) * rInfo.rewardPerDay / Σ(allUser's DepositByDay to day[i-1] - unstakedByDay)
    // i ∈ (0, 365]
    function CalculateReward()
        public
        view
        returns (uint256 reward, uint256 gap)
    {
        gap = _gapDays(block.timestamp, rCfg.startAt);
        if (gap > 365) {
            gap = 365;
        }
        uint256 totalStakedByNow = 0; // total staked amount from day 0 to day last
        uint256 userTotalStakedByNow = 0; // user staked amount from day 0 to day last
        for (uint16 i = 0; i < userTotalStakeMap[msg.sender].userRewardedByDay; i++) {
            userTotalStakedByNow =
                userTotalStakedByNow +
                userStakeMap[i].userStakeByDay[msg.sender].stake -
                userStakeMap[i].userStakeByDay[msg.sender].unstake;

            if (
                userStakeMap[i].totalStakeAmount > 0 ||
                userStakeMap[i].totalUnstakeAmount > 0
            ) {
                totalStakedByNow =
                    totalStakedByNow +
                    userStakeMap[i].totalStakeAmount -
                    userStakeMap[i].totalUnstakeAmount;
            }
        }

        reward = 0;
        for (
            uint16 i = uint16(userTotalStakeMap[msg.sender].userRewardedByDay + 1);
            i <= gap;
            i++
        ) {
            if (
                userStakeMap[i - 1].totalStakeAmount == 0 &&
                totalStakedByNow == 0
            ) {
                continue;
            }
            if (
                userStakeMap[i - 1].totalStakeAmount > 0 ||
                userStakeMap[i - 1].totalUnstakeAmount > 0
            ) {
                totalStakedByNow =
                    totalStakedByNow +
                    userStakeMap[i - 1].totalStakeAmount -
                    userStakeMap[i - 1].totalUnstakeAmount;
            }
            userTotalStakedByNow =
                userTotalStakedByNow +
                userStakeMap[i - 1].userStakeByDay[msg.sender].stake -
                userStakeMap[i - 1].userStakeByDay[msg.sender].unstake;
            reward +=
                (userTotalStakedByNow * rInfo.rewardPerDay) /
                totalStakedByNow;
        }
        return (reward, gap);
    }

    function _claimRewards(uint256 amount) private {
        _transferRewardToken(msg.sender, amount);
        // record reward balance
        rInfo.rewardBalance -= amount;
        emit e_ClaimReward(amount, msg.sender);

        return;
    }

    // Stake part
    function Stake(uint256 amount) public checkEnd {
        // use erc20 transfer for this contract is staking erc20 token
        safeTransferFrom(
            rInfo.rewardTokenAddress,
            msg.sender,
            address(this),
            amount
        );

        _recordStake(amount);

        emit e_Stake(amount, msg.sender);

        return;
    }

    function _recordStake(uint256 amount) private {
        // total
        rInfo.totalStakeBalance += amount;
        userTotalStakeMap[msg.sender].userTotalStakeAmount += amount;
        // by day
        uint16 gap = uint16(_gapDays(block.timestamp, rCfg.startAt));
        userStakeMap[gap].totalStakeAmount += amount;
        userStakeMap[gap].userStakeByDay[msg.sender].stake += amount;
    }

    function Unstake(uint256 amount) public {
        require(
            userTotalStakeMap[msg.sender].userTotalStakeAmount >= amount,
            "Insufficient staked amount"
        );
        IERC20(rInfo.rewardTokenAddress).transfer(msg.sender, amount);
        // record unstake
        userTotalStakeMap[msg.sender].userTotalStakeAmount -= amount;
        uint16 gap = uint16(_gapDays(block.timestamp, rCfg.startAt));
        userStakeMap[gap].userStakeByDay[msg.sender].unstake += amount;
        
        rInfo.totalStakeBalance -= amount;
        userStakeMap[gap].totalUnstakeAmount += amount;
    }

    function balanceOfRewardToken() public view returns (uint256) {
        return IERC20(rInfo.rewardTokenAddress).balanceOf(address(this));
    }

    function _transferRewardToken(
        address to,
        uint256 amount
    ) internal returns (bool) {
        require(rInfo.rewardBalance >= amount, "Insufficient balance");
        return IERC20(rInfo.rewardTokenAddress).transfer(to, amount);
    }

    function renounceOwnership() public virtual override onlyOwner {
        require(WithdrawAccount != address(0), "WithdrawAccount is not set");

        _transferOwnership(address(0));
    }

    function rescueERC20(
        address token,
        address to,
        uint256 amount
    ) external withdrawOrOwner returns (bool) {
        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );
        require(_gapDays(block.timestamp, rCfg.startAt) > 365, "Not ended");
        return IERC20(token).transfer(to, amount);
    }

    function rescureETH(address to, uint256 amount) external withdrawOrOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        require(_gapDays(block.timestamp, rCfg.startAt) > 365, "Not ended");
        (bool sent, ) = to.call{value: amount}("");
        require(sent, "Failed to withdraw Ether");
    }

    // getters
    function getStakedAmountByDay(uint16 day) public view returns (uint256) {
        return userStakeMap[day].totalStakeAmount;
    }

    function getStakedAmountByDayAndAddress(
        uint16 day,
        address depositor
    ) public view returns (UserStakeByDay memory) {
        return userStakeMap[day].userStakeByDay[depositor];
    }

    // EndAt is set to 365 days after contract creation
    modifier checkEnd() {
        require(block.timestamp < rCfg.endAt, "End");
        _;
    }

    function _setWithdraw(address withdraw) public onlyOwner returns (bool) {
        WithdrawAccount = withdraw;
        return true;
    }

    function _checkWithdraw() internal view virtual {
        if (owner() != address(0) && owner() != _msgSender()) {
            revert UnauthorizedWithdrawAccount(_msgSender());
        }
        if (owner() == address(0) && WithdrawAccount != _msgSender()) {
            revert UnauthorizedWithdrawAccount(_msgSender());
        }
    }

    modifier withdrawOrOwner() {
        _checkWithdraw();
        _;
    }

    // date handling
    function _getTodayZero(uint256 timestamp) private pure returns (uint256) {
        return timestamp - (timestamp % 86400);
    }

    // gapDays returns gap days between timestamp and rCfg.startAt
    function _gapDays(
        uint256 timestamp,
        uint256 startAt
    ) private pure returns (uint256) {
        require(timestamp >= startAt, "Invalid timestamp");
        return (_getTodayZero(timestamp) - startAt) / 86400;
    }

    function getDayGapFromStart() public view returns (uint256) {
        return _gapDays(block.timestamp, rCfg.startAt);
    }
}