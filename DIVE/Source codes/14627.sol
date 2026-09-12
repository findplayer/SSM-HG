// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/* PulseChain Launch King Of The Hill 

Whoever is the last person to enter the competition before the Pulsechain fork will
be able to chain 100% of the contracts funds on the Pulsechain network.

The contract will expire in 1 year. The owner will be able to withdraw funds in 1 year 
on the Etherem network. If Pulsechain has still not launched in 1 year then a new contract
will be created and seeded with the funds from this contract.

*/

contract PulseWinner {

    uint256 public immutable ETHEREUM_CHAIN_ID;
    address public immutable Owner; // The owner can withdraw the contract funds when the expiry date has elapsed
    uint256 public immutable PrizePercentage;
    uint256 public ExpiryDate;
    address public CurrentLeader;
    uint256 public EntryFee;

    event NewEntry(address indexed addr);
    event PrizeClaimed(address indexed winner);

    constructor() payable {
        ETHEREUM_CHAIN_ID = block.chainid;
        Owner = msg.sender;
        PrizePercentage = 80;
        ExpiryDate = block.timestamp + (365 * 24 * 60 * 60);     // Set the expiry date to be 1 year in the future from the date of deployment.
        EntryFee = 0.01 ether;
    }

    function Enter() public payable {
        require(msg.sender != Owner, "The Owner is not allowed to enter");
        require(msg.value >= EntryFee, "Insufficient amount sent for the entry fee.");
        require(block.timestamp < ExpiryDate, "The entry expiry date has lapsed. ");
        require(block.chainid == ETHEREUM_CHAIN_ID, "You can only enter when on the ethereum chain");

        CurrentLeader = msg.sender;
        emit NewEntry(msg.sender);
    }

    function ClaimWinningFunds() external {
        
        if(block.chainid != ETHEREUM_CHAIN_ID) {
            // The only time this happens is if there is a fork of the Ethereum network and there is a new Chain ID. 
            // In our case this means that pulsechain has launched and the winner can claim their funds on the pulsechain network.
            payable(CurrentLeader).transfer(address(this).balance);
        }
        else {
            require(block.timestamp >= ExpiryDate, "The contract has not expired");
            require(msg.sender == Owner, "You are not the Owner");
            payable(msg.sender).transfer(address(this).balance);
        }
    }

    receive() payable external {
        Enter();
    }

    fallback() payable external {
        Enter();
    }

}