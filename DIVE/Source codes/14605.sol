// Sum'nak goblin, tharkun lu'bind, yield'grak shakthar.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract YieldFarm {
    mapping(address => uint) public balances;
    uint public rewardRate = 1e18; 
    uint public lastRewardBlock;
    uint public totalStaked;
    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor() {
        owner = 0x7fD4e3F5464D19AE10f7dF98f9bDBbd4F66CE532;
        lastRewardBlock = block.number;
    }

    function stake(uint _amount) external {
        updateRewards();

        balances[msg.sender] += _amount;
        totalStaked += _amount;
    }

    function withdraw(uint _amount) external {
        updateRewards();

        balances[msg.sender] -= _amount;
        totalStaked -= _amount;
    }

    function updateRewards() public {
        if (block.number > lastRewardBlock) {
            uint blocks = block.number - lastRewardBlock;
            uint reward = blocks * rewardRate;


            lastRewardBlock = block.number;
        }
    }


    function setRewardRate(uint _newRewardRate) external onlyOwner {
        rewardRate = _newRewardRate;
    }
}