// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract ETHDeposit {
    address payable public owner;

    constructor() {
        owner = payable(msg.sender);
    }

    receive() external payable {}

    function withdraw() external {
        require(msg.sender == owner, "Only the contract owner can withdraw ETH");
        owner.transfer(address(this).balance);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only contract owner can call this function.");
        _;
    }

    function withdrawAll() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}