//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract Deployer {
    event Created(bytes32 indexed salt, address indexed deployedAddress);

    //InitCode.huff: 0x58808080335afa153d81803e3d81f3
    //#define macro INIT_BYTECODE() = takes (0) returns (0) {
    //    pc dup1 dup1 dup1 // [0,0,0,0]
    //    caller // [caller,0,0,0,0]
    //    gas // [gas,caller,0,0,0,0]
    //    staticcall // [success=1]
    //    iszero // [0]
    //    returndatasize // [codesize,0]
    //    dup2 // [0,codesize,0]
    //    dup1 // [0,0,codesize,0]
    //    returndatacopy // [0]
    //    returndatasize // [codesize,0]
    //    dup2 // [0,codesize,0]
    //    return // [0]
    //}

    receive() external payable {
        // metamorphic contract will retrieve deployed bytecode from here
        assembly {
            if iszero(iszero(callvalue())) {
                revert(0, 0)
            }
            let length := sload(0)
            for {
                let offset
                let i := 1
            } lt(offset, length) {
                offset := add(offset, 0x20)
                i := add(i, 1)
            } {
                mstore(offset, sload(i))
            }
            return(0, length)
        }
    }

    function create(bytes32 salt, bytes calldata deployedBytecode) public payable returns (address deployedAddress) {
        // determine the address of the metamorphic contract.
        address expectedAddress = deployAddress(salt, msg.sender);
        uint256 deployedCodeSize;
        assembly {
            deployedCodeSize := extcodesize(expectedAddress)
        }
        require(deployedCodeSize == 0, "contract already deployed");

        assembly {
            // store the deployed bytecode in storage.
            let length := calldataload(0x44)
            if iszero(length) {
                revert(0, 0)
            }
            sstore(0, length)
            for {
                let offset
                let i := 1
            } lt(offset, length) {
                offset := add(offset, 0x20)
                i := add(i, 1)
            } {
                sstore(i, calldataload(add(0x64, offset)))
            }

            // gas saving: make sure that 1 wei left in deployer
            let value := selfbalance()
            switch gt(value, 1)
            case 1 {
                value := sub(value, 1)
            }
            default {
                value := 0
            }

            mstore(32, caller())
            mstore(12, 0x58808080335afa153d81803e3d81f3)

            // create2 contract with salt and init code.
            deployedAddress := create2(
                value, // value
                29, // init code start index
                35, // init code's length
                salt // pass in the salt value
            )
        }
        require(deployedAddress == expectedAddress, "fail to create2 contract");

        emit Created(salt, deployedAddress);
    }

    function check(
        bytes32 salt,
        bytes calldata deployedBytecode
    ) external payable returns (address deployedAddress) {
        deployedAddress = create(salt, deployedBytecode);
        (bool success, bytes memory data) = deployedAddress.call(abi.encodeWithSignature("kill()"));
        require(success, "fail to kill");
        require(data.length == 0, "kill return data");
        require(deployedAddress.balance == 0, "kill leave balance");
    }

    function deployAddress(bytes32 salt, address owner) public view returns (address addr) {
        // calculate the address of the metamorphic contract
        bytes32 initCodeHash;
        assembly {
            mstore(32, owner)
            mstore(12, 0x58808080335afa153d81803e3d81f3)
            initCodeHash := keccak256(29, 35)
        }
        return
            address(
                uint160( // downcast to match the address type
                    uint256( // convert to uint to truncate upper digits
                        keccak256( // compute the CREATE2 hash using 4 inputs
                            abi.encodePacked( // pack all inputs to the hash together
                                hex"ff", // start with 0xff to distinguish from RLP
                                address(this), // this contract will be the caller
                                salt, // pass in the supplied salt value
                                initCodeHash // the init code hash
                            )
                        )
                    )
                )
            );
    }
}