/**
* Contract for LP staking for the Hibiki.finance token on the Ethereum network.
* Rewards are accrued from received tokens.
* The LP token for WETH-HIBIKI is: 0xF0aD9B5F6B8Ccd60806372Aa65f02cF7F02c69Cf
* The Hibiki token is: 0xA693032e8cfDB8115c6E72B60Ae77a1A592fe4bD
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

abstract contract Auth {
	address private owner;
	mapping (address => bool) private authorizations;

	constructor(address _owner) {
		owner = _owner;
		authorizations[_owner] = true;
	}

	/**
	* @dev Function modifier to require caller to be contract owner
	*/
	modifier onlyOwner() {
		require(isOwner(msg.sender), "!OWNER"); _;
	}

	/**
	* @dev Function modifier to require caller to be authorized
	*/
	modifier authorized() {
		require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
	}

	/**
	* @dev Authorize address. Owner only
	*/
	function authorize(address adr) public onlyOwner {
		authorizations[adr] = true;
	}

	/**
	* @dev Remove address' authorization. Owner only
	*/
	function unauthorize(address adr) public onlyOwner {
		authorizations[adr] = false;
	}

	/**
	* @dev Check if address is owner
	*/
	function isOwner(address account) public view returns (bool) {
		return account == owner;
	}

	/**
	* @dev Return address' authorization status
	*/
	function isAuthorized(address adr) public view returns (bool) {
		return authorizations[adr];
	}

	/**
	* @dev Transfer ownership to new address. Caller must be owner. Leaves old owner authorized
	*/
	function transferOwnership(address payable adr) public onlyOwner {
		owner = adr;
		authorizations[adr] = true;
		emit OwnershipTransferred(adr);
	}

	event OwnershipTransferred(address owner);
}

interface IERC20 {
	function transfer(address recipient, uint256 amount) external returns (bool);
	function balanceOf(address account) external view returns (uint256);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface Flow {
	function process() external;
}

contract VolumeStaking is Auth {

	struct Stake {
		uint256 amount;
		uint256 totalExcluded;
		uint256 totalRealised;
	}

	address public immutable stakingToken;
	address public rewardToken;
	address public hibikiFlow;
	uint256 public totalRealised;
	uint256 public totalStaked;

	mapping (address => Stake) public stakes;

	/**
	* @dev Make lower if the token has very high digits.
	*/
	uint256 private constant _accuracyFactor = 10 ** 36;
	uint256 private _rewardsPerToken;
	uint256 private _lastContractBalance;

	event Realised(address account, uint256 amount);
	event Staked(address account, uint256 amount);
	event Unstaked(address account, uint256 amount);

	error ZeroAmount();
	error InsufficientStake(uint256 attempted, uint256 available);
	error StakingTokenRescue();

	constructor (address _stakingToken, address _rewardToken, address flow) Auth(msg.sender) {
		stakingToken = _stakingToken;
		rewardToken = _rewardToken;
		hibikiFlow = flow;
	}

	function getTotalRewards() external view returns (uint256) {
		return totalRealised + IERC20(rewardToken).balanceOf(address(this));
	}

	function getCumulativeRewardsPerLP() external view returns (uint256) {
		return _rewardsPerToken;
	}

	function getLastContractBalance() external view returns (uint256) {
		return _lastContractBalance;
	}

	function getStake(address account) external view returns (Stake memory) {
		return stakes[account];
	}

	function getStakedAmount(address account) public view returns (uint256) {
		return stakes[account].amount;
	}

	function getRealisedEarnings(address staker) external view returns (uint256) {
		return stakes[staker].totalRealised;
	}

	function getUnrealisedEarnings(address staker) external view returns (uint256) {
		uint256 amount = getStakedAmount(staker);
		if (amount == 0) {
			return 0;
		}

		uint256 stakerTotalRewards = amount * _getCurrentRewardsPerToken() / _accuracyFactor;
		uint256 stakerTotalExcluded = stakes[staker].totalExcluded;

		if (stakerTotalRewards <= stakerTotalExcluded) {
			return 0;
		}

		return stakerTotalRewards - stakerTotalExcluded;
	}

	function getCumulativeRewards(uint256 amount) public view returns (uint256) {
		return amount * _rewardsPerToken / _accuracyFactor;
	}

	function stake(uint256 amount) external {
		if (amount == 0) {
			revert ZeroAmount();
		}
		IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
		_stake(msg.sender, amount);
	}

	function stakeFor(address staker, uint256 amount) external {
		if (amount == 0) {
			revert ZeroAmount();
		}

		IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
		_stake(staker, amount);
	}

	function stakeAll() external {
		uint256 amount = IERC20(stakingToken).balanceOf(msg.sender);
		if (amount == 0) {
			revert ZeroAmount();
		}

		IERC20(stakingToken).transferFrom(msg.sender, address(this), amount);
		_stake(msg.sender, amount);
	}

	/**
	* @dev Checks for HibikiFlow contract and processes it on unstakes and claims.
	* HibikiFlow buys and sends tokens to this contract when it has enough ether.
	*/
	function _checkFlow() private {
		if (hibikiFlow != address(0) && hibikiFlow.balance > 0) {
			try Flow(hibikiFlow).process() {} catch {}
		}
	}

	function unstake(uint256 amount) external {
		if (amount == 0) {
			revert ZeroAmount();
		}
		_checkFlow();

		_unstake(msg.sender, amount);
	}

	function forceUnstake(address account, uint256 amount) external authorized {
		if (amount == 0) {
			revert ZeroAmount();
		}
		_unstake(account, amount);
	}

	function unstakeAll() external {
		uint256 amount = getStakedAmount(msg.sender);
		if (amount == 0) {
			revert ZeroAmount();
		}
		_checkFlow();

		_unstake(msg.sender, amount);
	}

	function realise() external {
		_checkFlow();
		_realise(msg.sender);
	}

	function _realise(address staker) private {
		// Update rewards with received tokens.
		// It's important this is done before checks so new stakes do not dillute old stakes.
		_updateRewards();

		// Check first if there's a stake.
		if (getStakedAmount(staker) == 0) {
			return;
		}

		// Calculate accrued unclaimed reward.
		uint256 amount = earnt(staker);
		if (amount == 0) {
			return;
		}

		unchecked {
			stakes[staker].totalRealised += amount;
			stakes[staker].totalExcluded += amount;
			totalRealised += amount;
		}
		IERC20(rewardToken).transfer(staker, amount);
		_updateRewards();

		emit Realised(staker, amount);
	}

	function earnt(address staker) private view returns (uint256) {
		uint256 amount = getStakedAmount(msg.sender);
		if (amount == 0) {
			return 0;
		}

		uint256 stakerTotalRewards = getCumulativeRewards(amount);
		uint256 stakerTotalExcluded = stakes[staker].totalExcluded;
		if (stakerTotalRewards <= stakerTotalExcluded) {
			return 0;
		}

		return stakerTotalRewards - stakerTotalExcluded;
	}

	function _stake(address staker, uint256 amount) private {
		_realise(staker);

		// Add to current stake.
		// Note: If the token has humongous decimals or digits do check for overflow.
		unchecked {
			stakes[staker].amount += amount;
			stakes[staker].totalExcluded = getCumulativeRewards(stakes[staker].amount);
			totalStaked += amount;
		}

		emit Staked(staker, amount);
	}

	function _unstake(address staker, uint256 amount) private {
		uint256 stakedAmount = getStakedAmount(staker);
		if (stakedAmount < amount) {
			revert InsufficientStake(amount, stakedAmount);
		}

		// Realise staking gains.
		_realise(staker);

		// Remove the stake amount.
		unchecked {
			stakes[staker].amount -= amount;
			totalStaked -= amount;
		}
		stakes[staker].totalExcluded = getCumulativeRewards(stakes[staker].amount);
		IERC20(stakingToken).transfer(staker, amount);

		emit Unstaked(staker, amount);
	}

	function _distribute(uint256 amount) private returns (bool) {
		uint256 totalSt = totalStaked;
		if (totalSt == 0 || amount == 0) {
			return false;
		}

		_rewardsPerToken += amount * _accuracyFactor / totalSt;
		return true;
	}

	function _updateRewards() private {
		uint256 tokenBalance = IERC20(rewardToken).balanceOf(address(this));

		// Nothing to update if balance did not change.
		if (tokenBalance == _lastContractBalance) {
			return;
		}

		// Store rewards accrued with the new balance.
		if (tokenBalance > _lastContractBalance) {
			if (!_distribute(tokenBalance - _lastContractBalance)) {
				return;
			}
		}

		_lastContractBalance = tokenBalance;
	}

	function _getCurrentRewardsPerToken() private view returns (uint256) {
		uint256 total = totalStaked;
		if (total == 0) {
			return 0;
		}
		uint256 tokenBalance = IERC20(rewardToken).balanceOf(address(this));
		if (tokenBalance > _lastContractBalance) {
			uint256 newRewards = tokenBalance - _lastContractBalance;
			uint256 additionalAmountPerLP = newRewards * _accuracyFactor / total;
			return _rewardsPerToken + additionalAmountPerLP;
		}

		return _rewardsPerToken;
	}

	/**
	 * @dev Unstakes all at once ignoring token claims.
	 */
	function emergencyUnstakeAll() external {
		uint256 amount = stakes[msg.sender].amount;
		if (amount == 0) {
            revert ZeroAmount();
        }
		IERC20(stakingToken).transfer(msg.sender, amount);
		unchecked {
			totalStaked -= amount;
		}
		stakes[msg.sender].amount = 0;
	}

	function setRewardToken(address reward) external authorized {
		rewardToken = reward;
	}

	function setFlowAddress(address flow) external authorized {
		hibikiFlow = flow;
	}

	function rescueToken(address token) external authorized {
		if (token == stakingToken) {
			revert StakingTokenRescue();
		}
		IERC20 t = IERC20(token);
		t.transfer(msg.sender, t.balanceOf(address(this)));
	}
}