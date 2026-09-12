// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Ownable {
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address not allowed");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

contract GM is Ownable {
    string public constant name = "GM by ELON";
    string public constant symbol = "GM";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 10000000000000 * 10**uint256(decimals);

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isBot;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Burn(address indexed burner, uint256 value);
    event BotsUpdated(address indexed account, bool isBot);

    modifier notBot(address account) {
        require(!isBot[account], "Account is marked as a bot");
        _;
    }

    constructor() {
        balanceOf[msg.sender] = totalSupply;
    }

    function transfer(address to, uint256 value) external notBot(msg.sender) notBot(to) returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external notBot(from) notBot(to) returns (bool) {
        require(value <= allowance[from][msg.sender], "Insufficient allowance");
        allowance[from][msg.sender] -= value;
        _transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function burn(uint256 value) external onlyOwner {
        _burn(msg.sender, value);
    }

    function addBot(address bot) external onlyOwner {
        isBot[bot] = true;
        emit BotsUpdated(bot, true);
    }

    function removeBot(address bot) external onlyOwner {
        isBot[bot] = false;
        emit BotsUpdated(bot, false);
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "Transfer from the zero address");
        require(to != address(0), "Transfer to the zero address");
        require(value <= balanceOf[from], "Insufficient balance");

        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
    }

    function _burn(address burner, uint256 value) internal {
        require(value <= balanceOf[burner], "Insufficient balance for burn");
        balanceOf[burner] -= value;
        emit Burn(burner, value);
        emit Transfer(burner, address(0), value);
    }
}