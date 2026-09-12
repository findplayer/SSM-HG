// https://twitter.com/OHM_ERC404
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract OHMSTAKING {
    mapping(address => uint256) public stakes;
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

    function stakeTokens(uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        stakes[msg.sender] += amount;
        emit Staked(msg.sender, amount);
    }

    function unstakeTokens(uint256 amount) external {
        require(stakes[msg.sender] >= amount, "Not enough staked");
        stakes[msg.sender] -= amount;
        emit Unstaked(msg.sender, amount);
    }
}