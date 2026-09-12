// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

/** 
 * @title Cygnustream
 * @dev The Cygnustream smart contract.
 * You're gonna need a PhD to understand this one.
 * https://cygnustream.com
 */
contract Cygnustream {

    event Subscription(
        bytes32 indexed id,
        address indexed recipient,
        uint value
    );

    function subscribe(address payable _recipient, bytes32 _id) external payable {
        _recipient.transfer(msg.value);
        emit Subscription(_id, _recipient, msg.value);
    }
}