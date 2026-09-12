// SPDX-License-Identifier: MIT
// Reference: https://compare.chainstack.com/
// This contract is designed to compare node performance across different EVM chains.

pragma solidity ^0.8.0;

contract CompareNodePerformance {
    uint256 private counter;

    // Counters adjusted to roughly consume 100k gas in computational resources on the canonical Ethereum network.
    // This may change with network upgrades.
    uint256 private constant INCREMENT_LOOP_COUNT = 206;
    uint256 private constant COMPUTE_LOOP_COUNT = 103;

    uint256 private lastComputed;

    constructor() {
        counter = 0;
        lastComputed = 0;
    }

    // Simulates a read operation to consume computational resources in gas.
    // Note that the consumed gas may differ across different EVMs.
    // Used to run an eth_call to measure node performance by the Chainstack Compare tool.
    function callIncrementCounter() public view returns(uint256) {
        uint256 dummyCounter = counter;
        for (uint256 i = 0; i < INCREMENT_LOOP_COUNT; i++) {
            dummyCounter += 1;
        }
        return dummyCounter;
    }

    // Does a write operation to consume computational resources in gas.
    // Note that the consumed gas may differ across different EVMs.
    // The produced transaction hash is then used to run a debug_traceTransaction call to measure node performance by the Chainstack Compare tool. Callable by anyone.
    function writeComputeCounter() public {
        uint256 sum = 0;
        for (uint256 i = 0; i < COMPUTE_LOOP_COUNT; i++) {
            sum += i * counter;
        }
        lastComputed = sum;
    }
}