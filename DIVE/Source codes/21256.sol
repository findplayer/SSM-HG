pragma solidity ^0.4.17;

contract Tx {
    mapping (address => mapping (address => mapping(uint => uint))) public tranxs;
    function record(address _from, address _to, uint _value) public {
        tranxs[_from][_to][now] = _value;
    }
}