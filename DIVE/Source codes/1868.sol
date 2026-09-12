/**
 *Submitted for verification at BscScan.com on 2024-03-13
*/

/**
 *Submitted for verification at Etherscan.io on 2024-03-08
*/

/**
 *Submitted for verification at testnet.bscscan.com on 2024-03-07
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IWXETA {
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
    function burn(address from, uint256 amount) external returns(bool);
    function mint(address receiver, uint256 amount) external returns(bool);
}

contract XANABridgeFacet {
    bytes32 internal constant XETABRIDGENAMESPACE = keccak256('xetabridge.facet');

    struct XETABRIDGESTORAGE {
        bool initialized;

        address wxeta;
        address owner;
        uint256 chainId;
        uint256 depositId;
        uint256 releaseId;
        uint256 minDeposit;
        uint256 maxDeposit;

        mapping(address => bool) authorized;
        mapping(uint256 => bool) chainSupported;
        mapping(address => uint256) amountReleased;
        mapping(address => uint256) amountDeposited;
    }

    event BridgeBalanceTransfer(uint256 _amount, uint256 transferredAt, uint256 depositId);
    event Release(address user, uint256 amount, uint256 releasedAt, uint256 releaseId, address releasedBy);
    event Deposit(address user, uint256 amount, uint256 depositedAt, uint256 depositId, uint256 sourceChainId);

    function getXETABridgeStorage() internal pure returns(XETABRIDGESTORAGE storage s) {
        bytes32 position = XETABRIDGENAMESPACE;
        assembly {
            s.slot := position
        }
    }

    modifier notInitialized {
        require(getXETABridgeStorage().initialized != true, "already initialized");
        _;
    }

    function initialize(address _wXetaAddress) external notInitialized {
        XETABRIDGESTORAGE storage s = getXETABridgeStorage();
        s.initialized = true;
        s.owner = msg.sender;
        s.wxeta = _wXetaAddress;
        s.chainId = block.chainid;
        s.minDeposit = 100 * 1E18;
        s.maxDeposit = 100000 * 1E18;
        s.authorized[msg.sender] = true;
    }

    modifier onlyOwner() {
        require(msg.sender == getXETABridgeStorage().owner, "caller is not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(getXETABridgeStorage().authorized[msg.sender], "caller is not authorized");
        _;
    }

    /**
     * @dev PUBLIC FACING: Users can deposit their XETA on this contract
     * and recieve on XANAChain
     */
    function deposit(uint256 _amount) external {
        XETABRIDGESTORAGE storage s = getXETABridgeStorage();
        require(_amount >= s.minDeposit && _amount <= s.maxDeposit, "amount off limits");
        require(IWXETA(s.wxeta).burn(msg.sender, _amount), "wxeta burn failed");
        s.amountDeposited[msg.sender] += _amount;
        s.depositId++;
        emit Deposit(msg.sender, _amount, block.timestamp, s.depositId, s.chainId);
    }

    function release(address _user, uint256 _amount) external onlyAuthorized {
        XETABRIDGESTORAGE storage s = getXETABridgeStorage();
        require(_user != address(0), "cannot mint to zero address");
        require(_amount >= s.minDeposit && _amount <= s.maxDeposit, "amount off limits");
        require(IWXETA(s.wxeta).mint(_user, _amount), "release mint failed");
        s.amountReleased[msg.sender] += _amount;
        s.releaseId++;
        emit Release(msg.sender, _amount, block.timestamp, s.releaseId, msg.sender);
    }

    function emergencyWithdraw(address _receiver) external onlyOwner {
        XETABRIDGESTORAGE storage s = getXETABridgeStorage();
        uint256 balance = IWXETA(s.wxeta).balanceOf(address(this));
        require(IWXETA(s.wxeta).transfer(_receiver, balance));
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        XETABRIDGESTORAGE storage s = getXETABridgeStorage();
        s.owner = _newOwner;
    }

    function setDepositLimits(uint256 _min, uint256 _max) external onlyOwner {
        XETABRIDGESTORAGE storage s = getXETABridgeStorage();
        s.minDeposit = _min;
        s.maxDeposit = _max;
    }

    function setAuthorizedStatus(address _user, bool _status) external onlyOwner {
        XETABRIDGESTORAGE storage s = getXETABridgeStorage();
        s.authorized[_user] = _status;
    }

    function wxeta() external view returns(address) {
        return getXETABridgeStorage().wxeta;
    }

    function owner() external view returns(address) {
        return getXETABridgeStorage().owner;
    }

    function minDeposit() external view returns(uint256) {
        return getXETABridgeStorage().minDeposit;
    }

    function maxDeposit() external view returns(uint256) {
        return getXETABridgeStorage().maxDeposit;
    }

    function authorized(address _add) external view returns(bool) {
        return getXETABridgeStorage().authorized[_add];
    }

    function amountReleased(address _add) external view returns(uint256) {
        return getXETABridgeStorage().amountReleased[_add];
    }

    function amountDeposited(address _add) external view returns(uint256) {
        return getXETABridgeStorage().amountDeposited[_add];
    }

    function setChainSupported(uint256 _chainId, bool _status) external onlyOwner {
        getXETABridgeStorage().chainSupported[_chainId] = _status;
    }

    function setChainId(uint256 _id) external onlyOwner {
        getXETABridgeStorage().chainId = _id;
    }

    function chainId() external view returns(uint256) {
        return getXETABridgeStorage().chainId;
    }
}