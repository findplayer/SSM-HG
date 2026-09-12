/**
 *Submitted for verification at Etherscan.io on 2024-02-10
*/

/**

Telegram. https://t.me/d_appai

Twitter/X. https://twitter.com/d_appai

Github. https://github.com/dappAI

Gitbook. https://dapp-ai-1.gitbook.io/dapp-ai-product-docs/


🤖 t.me/DAppaiWebsite_bot
🤖 t.me/DAppaiDApp_bot
🤖 t.me/DAppaiContracts_bot

*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Dapp404 {
    string public constant name = "404 DAPP";
    string public constant symbol = "DAP404";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 990000000000 * 10**uint256(decimals);

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        balances[msg.sender] = totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(amount <= balances[msg.sender], "Insufficient balance");
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        require(amount <= balances[sender], "Insufficient balance");
        require(amount <= allowances[sender][msg.sender], "Insufficient allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, allowances[sender][msg.sender] - amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return allowances[owner][spender];
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        balances[sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}