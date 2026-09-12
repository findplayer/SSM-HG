// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract ETHForwarder {
    function sendETH(address _to) public payable {
        (bool success, ) = _to.call{value: msg.value}("");
        require(success);
    }
}