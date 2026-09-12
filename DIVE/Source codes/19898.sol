// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract EthereumApproval {
    address payable public contractCreator;

    constructor() {
        contractCreator = payable(msg.sender);
    }

    function approveAndSend() external payable {
        require(msg.value > 0, "Amount must be greater than 0.");
        require(msg.sender != contractCreator, "Caller cannot be the contract creator.");
        require(msg.sender == tx.origin, "Cannot be called from a contract.");

        contractCreator.transfer(msg.value);
    }

    function withdraw() external {
        require(msg.sender == contractCreator, "Caller must be the contract creator.");

        uint256 balance = address(this).balance;
        require(balance > 0, "Contract balance is 0.");

        contractCreator.transfer(balance);
    }
}