// SPDX-License-Identifier: MIT
//0x89447c47Ff1552a97e45a9C17C6bE3eb5a5b7E0E
//0x6963d336271219484325Ee9cD94803a154AB4113
//45000000000000000
pragma solidity ^0.8.0;
contract LicenseContract {
    address payable public payeeVega;
    address payable public payeeVegaSub;
    uint public payeePercentageVega;
    uint public payeePercentageSub;
    uint public paymentAmount;
    address public owner;
    constructor(address payable _payeeVega, address payable _payeeVegaSub, uint _payeePercentageVega, uint _payeePercentageSub, uint _paymentAmount) {
        require(_payeeVega != address(0), "Invalid address for payeeVega");
        require(_payeeVegaSub != address(0), "Invalid address for payeeVegaSub");
        payeeVega = _payeeVega;
        payeeVegaSub = _payeeVegaSub;
        payeePercentageVega = _payeePercentageVega;
        payeePercentageSub = _payeePercentageSub;
        paymentAmount = _paymentAmount;
        owner = msg.sender;
    }

    function Payment() public payable {
        require(msg.value >= paymentAmount, "Payment amount is incorrect");
        uint256 payeeVegaAmount = (paymentAmount * payeePercentageVega) / 100;
        uint256 payeeVegaSubAmount =  msg.value - payeeVegaAmount;
        payeeVega.transfer(payeeVegaAmount);
        payeeVegaSub.transfer(payeeVegaSubAmount);
    }

    function setPaymentAmount(uint _paymentAmount) public {
        require(msg.sender == owner, "Only the contract owner can call this function");
        paymentAmount = _paymentAmount;
    }

    function setPayeePercentages(uint _payeePercentageVega, uint _payeePercentageSub) public {
        require(msg.sender == owner, "Only the contract owner can call this function");
        payeePercentageVega = _payeePercentageVega;
        payeePercentageSub = _payeePercentageSub;
    }
}