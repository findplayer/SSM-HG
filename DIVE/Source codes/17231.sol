// SPDX-License-Identifier: GPL-3

pragma solidity 0.8.19;

/* @title Empty implementation of CrocSwapPolicy interface */

contract CrocPolicyShell {

    function transferGovernance (address, address, address)
        public { }

    function opsResolution (address, uint16,
                            bytes calldata) public { }

    function treasuryResolution (address, uint16,
                                 bytes calldata, bool) public { }

    function emergencyHalt (address, string calldata)
        public { }

    function invokePolicy (address, uint16, bytes calldata) public { }

    struct PolicyRule {
        bytes32 cmdFlags_;
        uint32 mandateTime_;
        uint32 expiryOffset_;
    }

    function setPolicy (address, uint16, PolicyRule calldata) public { }

    function forcePolicy (address, uint16, PolicyRule calldata policy)
        public { }

    function emergencyReset (address, uint16, string calldata) public { }

    function passesPolicy (PolicyRule memory, bytes calldata)
        public pure returns (bool) { return true; }

    function acceptsCrocAuthority() public payable returns (bool) { return false; }
}