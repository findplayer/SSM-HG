/*
First experimental implementation of Gambling & Staking powered by DN404 technology 
https://twitter.com/C4SH404
https://c4sh-404.gitbook.io/c4sh-404/
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TierManagement {
    mapping(address => uint256) public userToTier;

    event TierAssigned(address indexed user, uint256 tier);

    constructor() {}


    function purchaseToken() public {
        uint256 tier = determineTier();
        userToTier[msg.sender] = tier;
        emit TierAssigned(msg.sender, tier);
    }

    function Randomize() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender))) % 100;
    }


    function determineTier() private view returns (uint256) {
        uint256 randomNumber = Randomize();
        if (randomNumber < 50) { 
            return 1; // Tier 1
        } else if (randomNumber < 70) {
            return 2; // Tier 2
        } else if (randomNumber < 85) {
            return 3; // Tier 3
        } else if (randomNumber < 95) { 
            return 4; // Tier 4
        } else { // 5% chance
            return 5; // Tier 5
        }
    }

    function getTier(address user) public view returns (uint256) {
        return userToTier[user];
    }
}