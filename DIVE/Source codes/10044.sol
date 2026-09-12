// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract Hodler {
  // Payable address can send Ether via transfer or send
  address payable public owner;
  uint256 public releaseTimeInUnixSeconds;

  // Payable constructor can receive Ether
  constructor(uint256 _releaseInDays) payable {
      owner = payable(msg.sender);
      releaseTimeInUnixSeconds = block.timestamp + _releaseInDays * 24 * 60 * 60;
  }


  // Function to receive Ether. msg.data must be empty
  receive() external payable {
    if(msg.sender == owner)
    {
      if(block.timestamp >= releaseTimeInUnixSeconds)
      {
        withdraw();
      }
    }
  }

  // Fallback function is called when msg.data is not empty
  fallback() external payable {
    if(msg.sender == owner)
      {
        if(block.timestamp >= releaseTimeInUnixSeconds)
        {
          withdraw();
        }
      }
  }

  function unlockAndWithdraw() public {
    require(msg.sender == owner, "Don't try to steal my ether.");
    require(block.timestamp >= releaseTimeInUnixSeconds, "Stop trading, just hodl.");

    withdraw();
  }


  // Function to withdraw all Ether from this contract.
  function withdraw() private {
      // get the amount of Ether stored in this contract
      uint amount = address(this).balance;

      // send all Ether to owner
      (bool success, ) = owner.call{value: amount}("");
      require(success, "Oops, it is messed up.");
  }
}