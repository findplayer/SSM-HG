//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract BlockTimestamp {
    function getTimeStamp() public view returns (uint) {
        return block.timestamp;
    }
}