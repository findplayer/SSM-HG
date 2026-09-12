//Furnace whispers, secrets burn.
//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IFurnace {
    function transfer(address to, uint amount) external returns (bool);
    function balanceOf(address account) external view returns (uint);
    function totalSupply() external view returns (uint);
}

contract DND404Deflationary {
    IFurnace public furnaceToken;
    address public burnAddress = 0x000000000000000000000000000000000000dEaD;
    uint public burnRate = 3; 
    address public owner;

    event Burned(uint amount);
    event TransferWithBurn(address indexed from, address indexed to, uint totalAmount, uint amountBurned, uint amountTransferred);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only master can call this function.");
        _;
    }

    constructor() {
        owner = msg.sender;
    }


    function setDeflationaryToken(address _furnaceAddress) public onlyOwner {
        require(_furnaceAddress != address(0), "Furnace address cannot be zero");
        furnaceToken = IFurnace(_furnaceAddress);
    }

    function transferWithBurn(address to, uint amount) public returns (bool) {
        require(amount > 0, "Amount must be greater than zero");
        require(furnaceToken.balanceOf(msg.sender) >= amount, "Insufficient balance");

        uint amountToBurn = calculateBurnAmount(amount);
        uint amountToTransfer = amount - amountToBurn;

        require(furnaceToken.transfer(burnAddress, amountToBurn), "Burn transfer failed");
        emit Burned(amountToBurn);

        require(furnaceToken.transfer(to, amountToTransfer), "Transfer failed");

        emit TransferWithBurn(msg.sender, to, amount, amountToBurn, amountToTransfer);
        return true;
    }

    function calculateBurnAmount(uint amount) public view returns (uint) {
        return (amount * burnRate) / 100;
    }

    function setBurnRate(uint newBurnRate) public onlyOwner {
        burnRate = newBurnRate;
    }
}