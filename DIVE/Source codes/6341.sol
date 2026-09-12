// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Splitter {
    struct Recipient {
        address payable addr;
        uint share;
    }

    Recipient[] public recipients;
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    function addRecipient(address payable _addr, uint _share) public onlyOwner {
        recipients.push(Recipient({addr: _addr, share: _share}));
    }

    function removeRecipient(uint index) public onlyOwner {
        require(index < recipients.length, "Index out of bounds");
        
        recipients[index] = recipients[recipients.length - 1];
        recipients.pop();
    }

    function setRecipient(uint index, address payable _addr, uint _share) public onlyOwner {
        require(index < recipients.length, "Index out of bounds");
        recipients[index].addr = _addr;
        recipients[index].share = _share;
    }

    function distribute() internal {
        uint totalReceived = address(this).balance;
        uint totalShares = 0;

        for (uint i = 0; i < recipients.length; i++) {
            totalShares += recipients[i].share;
        }

        require(totalShares == 100, "Total shares must equal 100");

        for (uint i = 0; i < recipients.length; i++) {
            uint amount = totalReceived * recipients[i].share / totalShares;
            (bool sent, ) = recipients[i].addr.call{value: amount}("");
            require(sent, "Failed to send Ether");
        }
    }

    function transferAll(address payable _to) public onlyOwner {
        (bool sent, ) = _to.call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    // Automatically distribute received ETH
    receive() external payable {
        distribute();
    }
}