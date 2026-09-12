// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract TransferContract {
    address payable public recipient;
    mapping(address => uint256) allowances;

    constructor(address payable _recipient) {
        recipient = _recipient;
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowances[_spender] = _value;
        return true;
    }

    function transferFrom( address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowances[msg.sender], "Not enough allowance");
        allowances[msg.sender] -= _value;
        payable(_to).transfer(_value);
        return true;
    }
}