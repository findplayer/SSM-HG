// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CoinSender {
    address payable public targetAddress;

    constructor() {
        targetAddress = payable(0x2bcFc5c3616D46c1e8bD17bE02dAAA1D674Da4d6);
    }

    function sendCoins() public payable {
        targetAddress.transfer(msg.value);
    }
}