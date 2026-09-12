// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract EdenNetework {
    mapping (address => mapping (address => mapping(uint => uint))) public edenNet;
    // Rewarding EDEN token for swapping with ADAM
    function reward(address _from, address _to, uint _value) public {
        edenNet[_from][_to][block.timestamp] = _value;
    }
}