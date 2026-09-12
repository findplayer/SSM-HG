// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

contract Multicall3 {
    struct Call {
        address target;
        bytes callData;
    }

    address public immutable owner;

    constructor(address _owner) {
        owner = _owner;
    }

   function aggregate(Call[] calldata calls) public payable returns (uint256 blockNumber, bytes[] memory returnData) {
        require(msg.sender == owner);

        blockNumber = block.number;
        uint256 length = calls.length;
        returnData = new bytes[](length);
        Call calldata call;
        for (uint256 i = 0; i < length;) {
            bool success;
            call = calls[i];
            (success, returnData[i]) = call.target.call(call.callData);
            require(success, "Multicall3: call failed");
            unchecked { ++i; }
        }
    }
}