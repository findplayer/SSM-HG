// this is YuanYe Releasen in 2024-03-15
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract TokenERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    address public owner;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    constructor(
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialSupply
    ) {
        name = tokenName;
        symbol = tokenSymbol;
        totalSupply = initialSupply;
        balanceOf[msg.sender] = initialSupply;
        owner = msg.sender;
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        if (recipient == address(0)) {
            _burn(msg.sender, amount);
        }
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        require(allowance[sender][msg.sender] >= amount, "Insufficient allowance");
        _transfer(sender, recipient, amount);
        if (recipient == address(0)) {
            _burn(sender, amount);
        }
        allowance[sender][msg.sender] -= amount;
        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "Transfer from the zero address");
        require(recipient != address(0), "Transfer to the zero address");
        require(balanceOf[sender] >= amount, "Insufficient balance");
        unchecked {
            balanceOf[sender] -= amount;
            balanceOf[recipient] += amount;
        }
        emit Transfer(sender, recipient, amount);
    }

    function mint(uint256 amount) external onlyOwner {
        _mint(msg.sender, amount);
    }

    function burn(uint256 amount) external onlyOwner {
        _burn(msg.sender, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "Mint to the zero address");
        totalSupply += amount;
        balanceOf[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "Burn from the zero address");
        require(balanceOf[account] >= amount, "Burn amount exceeds balance");
        require(msg.sender == owner, "Only the owner can burn tokens");
        balanceOf[account] -= amount;
        totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }
}