// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    function mul(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a * b;

        require(c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256));
        require((b == 0) || (c / b == a), 'mul overflow');
        return c;
    }

    function div(int256 a, int256 b) internal pure returns (int256) {
        require(b != -1 || a != MIN_INT256);

        return a / b;
    }

    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a),
            'sub overflow');
        return c;
    }

    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a),
            'add overflow');
        return c;
    }

    function abs(int256 a) internal pure returns (int256) {
        require(a != MIN_INT256,
            'abs overflow');
        return a < 0 ? -a : a;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, 'SafeMath: addition overflow');

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, 'SafeMath: subtraction overflow');
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, 'SafeMath: multiplication overflow');

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, 'SafeMath: division by zero');
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0,
            'parameter 2 can not be 0');
        return a % b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}

interface IBEP20 {

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address who) external view returns (uint256);

    function allowance(address owner, address spender)
    external
    view
    returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);

    function approve(address spender, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

contract Ownable {
    address private _owner;

    event OwnershipRenounced(address indexed previousOwner);
    event TransferOwnerShip(address indexed previousOwner);

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _owner = msg.sender;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, 'Not owner');
        _;
    }

    function renounceOwnership() public onlyOwner {
        emit OwnershipRenounced(_owner);
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        emit TransferOwnerShip(newOwner);
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0),
            'Owner can not be 0');
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract TokenFarm is Ownable {

    using SafeMath for uint256;
    using SafeMathInt for int256;

    struct UserInfo {
        uint256 amount;     // How many tokens the user has provided.
        uint256 stakingTime; // The time at which the user staked tokens.
        uint256 rewardClaimed; // The amount of reward claimed by the user.
    }

    struct PoolInfo {
        address tokenAddress;
        address rewardTokenAddress;
        uint256 maxPoolSize; 
        uint256 currentPoolSize;
        uint256 maxContribution;
        uint256 apy; // it is in 1000 times, so 1000 means 100%
        uint256 emergencyFees; // it is the fees in percentage, final fees is emergencyFees/1000
        uint256 minLockDays;
        uint256 totalRewardsClaimed; // total rewards claimed by the users
        bool poolType; // true for public staking, false for whitelist staking
        bool poolActive;
    }

    // Info of each pool.
    PoolInfo[] public poolInfo;
    uint256 [] public rewardTimes;
    bool lock_= false;

    uint256 public totalRewardsClaimed = 0;
    uint256 public referralPercent = 5;
    // Info of each user that stakes tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (uint256 => mapping (address => bool)) public whitelistedAddress;
    mapping (uint256 => uint256) public rewardAmount;
    mapping (uint256 => uint256) public rewardCurrentPoolSize;
    mapping (address => address) public refferalConnection; // it tell 1st address was reffered by 2nd address


    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);


    constructor () {
        
    }


    modifier lock {
        require(!lock_, "Process is locked");
        lock_ = true;
        _;
        lock_ = false;
    }

    function poolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function addPool (address _tokenAddress, address _rewardTokenAddress, uint256 _maxPoolSize, uint256 _maxContribution, uint256 _apy, uint256 _minLockDays, bool _poolType, bool _poolActive) public onlyOwner {
        poolInfo.push(PoolInfo({
            tokenAddress: _tokenAddress,
            rewardTokenAddress: _rewardTokenAddress,
            maxPoolSize: _maxPoolSize,
            currentPoolSize: 0,
            maxContribution: _maxContribution,
            apy: _apy,
            emergencyFees: 0,
            minLockDays: _minLockDays,
            poolType: _poolType,
            poolActive: _poolActive,
            totalRewardsClaimed: 0
        }));
    }

    function updateMaxPoolSize (uint256 _pid, uint256 _maxPoolSize) public onlyOwner{
        require (_pid < poolLength(), "Invalid pool ID");
        require (_maxPoolSize >= poolInfo[_pid].currentPoolSize, "Cannot reduce the max size below the current pool size");
        poolInfo[_pid].maxPoolSize = _maxPoolSize;
    }

    function updateMaxContribution (uint256 _pid, uint256 _maxContribution) public onlyOwner{
        require (_pid < poolLength(), "Invalid pool ID");
        poolInfo[_pid].maxContribution = _maxContribution;
    }

    function updateEmergencyFees (uint256 _pid, uint256 _emergencyFees) public onlyOwner {
        require (_pid < poolLength(), "Invalid pool ID");
        if (poolInfo[_pid].currentPoolSize > 0){
            require (_emergencyFees <= poolInfo[_pid].emergencyFees, "You can't increase the emergency fees when people started staking");
        }
        poolInfo[_pid].emergencyFees = _emergencyFees;
    }

    function updateMinLockDays (uint256 _pid, uint256 _lockDays) public onlyOwner {
        require (_pid < poolLength(), "Invalid pool ID");
        poolInfo[_pid].minLockDays = _lockDays;
    }

    function updateApy (uint256 _pid, uint256 _apy) public onlyOwner {
        require (_pid < poolLength(), "Invalid pool ID");
        poolInfo[_pid].apy = _apy;
    }

    function updatePoolType (uint256 _pid, bool _poolType) public onlyOwner {
        require (_pid < poolLength(), "Invalid pool ID");
        poolInfo[_pid].poolType = _poolType;
    }

    function updatePoolActive (uint256 _pid, bool _poolActive) public onlyOwner {
        require (_pid < poolLength(), "Invalid pool ID");
        poolInfo[_pid].poolActive = _poolActive;
    }

    function updateReferralPercent (uint256 _referralPercent) public onlyOwner {
        referralPercent = _referralPercent;
    }

    function addWhitelist (uint256 _pid, address [] memory _whitelistAddresses) public onlyOwner {
        require (_pid < poolLength(), "Invalid pool ID");
        uint256 length = _whitelistAddresses.length;
        require (length<= 200, "Can add only 200 wl at a time");
        for (uint256 i = 0; i < length; i++){
            address _whitelistAddress = _whitelistAddresses[i];
            whitelistedAddress[_pid][_whitelistAddress] = true;
        }
    }

    function addReward (uint256 _amount) public onlyOwner {
        rewardTimes.push(block.timestamp);
        rewardAmount[block.timestamp] = _amount;
        rewardCurrentPoolSize[block.timestamp] = poolInfo[0].currentPoolSize;
    }

    function emergencyLock (bool _lock) public onlyOwner {
        lock_ = _lock;
    }

    function stakeTokens (uint256 _pid, uint256 _amount, address refferal) public {
        require (_pid < poolLength(), "Invalid pool ID");
        require (poolInfo[_pid].poolActive, "Pool is not active");
        require (poolInfo[_pid].currentPoolSize.add(_amount) <= poolInfo[_pid].maxPoolSize, "Staking exceeds max pool size");
        require ((userInfo[_pid][msg.sender].amount).add(_amount) <= poolInfo[_pid].maxContribution , "Max Contribution exceeds");
        require (refferal != msg.sender, 'You can not reffer yourself');
        if (poolInfo[_pid].poolType == false){
            require (whitelistedAddress[_pid][msg.sender], "You are not whitelisted for this pool");
        }

        // Sending the claimable tokens to the user
        if (claimableRewards(_pid, msg.sender) > 0){
            claimRewards(_pid);
        }

        address _tokenAddress = poolInfo[_pid].tokenAddress;
        IBEP20 token = IBEP20 (_tokenAddress);
        bool success = token.transferFrom(msg.sender, address(this), _amount);
        require (success, "Transfer From failed. Please approve the token");

        poolInfo[_pid].currentPoolSize = (poolInfo[_pid].currentPoolSize).add(_amount);
        uint256 _stakingTime = block.timestamp; 
        _amount = _amount.add(userInfo[_pid][msg.sender].amount);
        uint256 _rewardClaimed = 0;
        userInfo[_pid][msg.sender] = UserInfo ({
            amount: _amount,
            stakingTime: _stakingTime,
            rewardClaimed: _rewardClaimed
        });

        // if user has no refferal
        if (refferalConnection[msg.sender] == address(0)) {
            refferalConnection[msg.sender] = refferal;
        }

        // 1st level refferal
        uint256 refferalLevel1 = _amount * referralPercent / 100;
        address refferalAddress1 = refferalConnection[msg.sender];
        if (refferalAddress1 != address(0)) {
            token.transfer(refferalAddress1, refferalLevel1);
        }

    }

    function claimableRewards (uint256 _pid, address _user) public view returns (uint256) {
        require (_pid < poolLength(), "Invalid pool ID");

        uint256 _stakingTime = userInfo[_pid][_user].stakingTime;
        uint256 lockDays = (block.timestamp - _stakingTime) / 1 days;
        if(lockDays < poolInfo[_pid].minLockDays) return 0;
        if (userInfo[_pid][_user].amount == 0) return 0;

        uint256 _claimableReward = 0;
        for (uint256 i = 0; i < rewardTimes.length; i++){
            uint256 _rewardTime = rewardTimes[i];
            uint256 _rewardAmount = rewardAmount[_rewardTime];
            uint256 _rewardCurrentPoolSize = rewardCurrentPoolSize[_rewardTime];
            if (_rewardTime > _stakingTime){
                uint256 _refundValue = ((userInfo[_pid][_user].amount * _rewardAmount) / (_rewardCurrentPoolSize));
                _claimableReward = _claimableReward.add(_refundValue);
            }
        }
        if (userInfo[_pid][_user].rewardClaimed >= _claimableReward) return 0;
        return _claimableReward - userInfo[_pid][_user].rewardClaimed;
    }

    function claimableNativeRewards (uint256 _pid, address _user) public view returns (uint256) {
        require (_pid < poolLength(), "Invalid pool ID");

        uint256 lockDays = (block.timestamp - userInfo[_pid][_user].stakingTime) / 1 days;
        uint256 _refundValue = ((userInfo[_pid][_user].amount *  poolInfo[_pid].apy * lockDays) / (1000 * 365));
        return _refundValue;
    }

    function unstakeTokens (uint256 _pid) public {
        require (_pid < poolLength(), "Invalid pool ID");
        require (userInfo[_pid][msg.sender].amount > 0 , "You don't have any staked tokens");
        require (userInfo[_pid][msg.sender].stakingTime > 0 , "You don't have any staked tokens");
        
        address _tokenAddress = poolInfo[_pid].tokenAddress;
        IBEP20 token = IBEP20 (_tokenAddress);
        address _rewardTokenAddress = poolInfo[_pid].rewardTokenAddress;
        IBEP20 rewardToken = IBEP20 (_rewardTokenAddress);
        uint256 _amount = userInfo[_pid][msg.sender].amount;

        uint256 _refundValue = claimableRewards(_pid, msg.sender);
        uint256 _nativeReward = claimableNativeRewards(_pid, msg.sender);
        userInfo[_pid][msg.sender].rewardClaimed += _refundValue;
        poolInfo[_pid].currentPoolSize = (poolInfo[_pid].currentPoolSize).sub(userInfo[_pid][msg.sender].amount);
        poolInfo[_pid].totalRewardsClaimed += _refundValue;
        userInfo[_pid][msg.sender].amount = 0;

        bool success1 = token.transfer(msg.sender, _amount);
        bool success2 = token.transfer(msg.sender, _nativeReward);
        bool success3 = rewardToken.transfer(msg.sender, _refundValue);
        require(success1 && success2 && success3, "Transfer failed");
    }

    function claimRewards (uint256 _pid) public {
        require (_pid < poolLength(), "Invalid pool ID");
        require (userInfo[_pid][msg.sender].amount > 0 , "You don't have any staked tokens");
        require (userInfo[_pid][msg.sender].stakingTime > 0 , "You don't have any staked tokens");

        address _rewardTokenAddress = poolInfo[_pid].rewardTokenAddress;
        IBEP20 rewardToken = IBEP20 (_rewardTokenAddress);
        uint256 _refundValue = claimableRewards(_pid, msg.sender);
        userInfo[_pid][msg.sender].rewardClaimed += _refundValue;
        poolInfo[_pid].totalRewardsClaimed += _refundValue;
        bool success = rewardToken.transfer(msg.sender, _refundValue);
        require(success, "Transfer failed");
    }

    // this function is to withdraw BNB sent to this address by mistake
    function withdrawEth () external onlyOwner returns (bool) {
        uint256 balance = address(this).balance;
        (bool success, ) = payable(msg.sender).call{
            value: balance
        }("");
        return success;
    }

    // this function is to withdraw BEP20 tokens sent to this address by mistake
    function withdrawBEP20 (address _tokenAddress) external onlyOwner returns (bool) {
        IBEP20 token = IBEP20 (_tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        bool success = token.transfer(msg.sender, balance);
        return success;
    }
}