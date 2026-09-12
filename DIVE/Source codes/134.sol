// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
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

contract Authorized is Context {
    address private _owner;
    mapping(address => bool) private _isAuthorized;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event AuthorizationChanged(address indexed account, bool isAuthorized);

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        _isAuthorized[msgSender] = true;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Authorized: caller is not the owner");
        _;
    }

    modifier onlyAuthorized() {
        require(_isAuthorized[_msgSender()], "Authorized: caller is not authorized");
        _;
    }

    function setAuthorization(address account, bool isAuthorized) public onlyOwner {
        _isAuthorized[account] = isAuthorized;
        emit AuthorizationChanged(account, isAuthorized);
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _isAuthorized[_owner] = false;
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Authorized: new owner is the zero address");
        _isAuthorized[newOwner] = true;
        _isAuthorized[_owner] = false;
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract CloudinaryFundStorage is Context, Authorized {    
    mapping(address => uint256) public etherBalances;

    event EtherReceived(address indexed from, uint256 amount);
    event ERC20Withdrawn(address indexed sender, address token, uint256 amount, address to);
    event ETHWitdrawm(address indexed sender, uint256 amount, address to);

    function getEtherBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function getTokenBalance(address tokenAddress) public view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    function transferERC20(address tokenAddress, uint256 amount, address recipient) public onlyAuthorized {
        IERC20 token = IERC20(tokenAddress);
        require(token.transfer(recipient, amount), "Transfer failed");
        emit ERC20Withdrawn(_msgSender(), tokenAddress, amount, recipient);
    }

    function withdrawAllERC20(address tokenAddress, address recipient) public onlyAuthorized {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(recipient, balance), "Transfer failed");
        emit ERC20Withdrawn(_msgSender(), tokenAddress, balance, recipient);
    }

    function withdrawEther(uint256 amount, address recipient) public onlyAuthorized {
        require(amount <= address(this).balance, "Insufficient balance");
        payable(recipient).transfer(amount);
        emit ETHWitdrawm(_msgSender(), amount, recipient);
    }

    function withdrawAllEther(address recipient) public onlyAuthorized {
        uint256 amount = address(this).balance;
        payable(recipient).transfer(amount);
        emit ETHWitdrawm(_msgSender(), amount, recipient);
    }

    receive() external payable {
        etherBalances[msg.sender] += msg.value;
        emit EtherReceived(msg.sender, msg.value);
    }
}