pragma solidity ^0.8.0;

// SPDX-License-Identifier: MIT

contract CREATE2 {
    address public owner;
    
    receive() external payable {}

    fallback() external payable {}

    modifier onlyOwner() {
        require(
            tx.origin == owner,
            "Caller is not an owner"
        );
        _;
    }

    constructor() {
        owner = tx.origin;
    }

    function call(
        address target,
        bytes calldata data,
        uint256 value
    ) public onlyOwner {
        (bool success, bytes memory returnData) = target.call{value: value}(
            data
        );
        require(success, string(returnData));
    }
}

contract CREATE2Creator {
    

    function CREATE2Contract(bytes32 salt) private returns (address) {
        CREATE2 _contract = new CREATE2{salt: salt}();
        return address(_contract);
    }

    function getBytecode() private pure returns (bytes memory) {
        bytes memory bytecode = type(CREATE2).creationCode;
        return abi.encodePacked(bytecode);
    }

    function calculateAddress(bytes32 salt) public view returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(
                bytes1(0xff),
                address(this),
                salt,
                keccak256(getBytecode())
            )
        );

        return address(uint160(uint256(hash)));
    }

    function CREATEAndCall(
        bytes32 salt,
        address to,
        bytes calldata data,
        uint256 value
    ) public {
        address contractAddress = CREATE2Contract(salt);

        bytes memory callData = abi.encodeWithSignature(
            "call(address,bytes calldata,uint256)",
            to,
            data,
            value
        );

        (bool success, ) = contractAddress.call(callData);
        require(success, "Fail");
    }

    function CREATE(
        bytes32 salt
    ) public {
        CREATE2Contract(salt);
    }
}