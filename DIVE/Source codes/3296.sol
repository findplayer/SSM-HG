// the first deflationary ERC-404 featuring a 1% token burn mechanism applied to each transaction
// https://twitter.com/Furnace404
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IFurnace {
    function transfer(address to, uint amount) external returns (bool);
    function balanceOf(address account) external view returns (uint);
    function burn(uint amount) external;
}

contract DeflationaryMechanism {
    IFurnace public furnaceToken;
    address public owner;
    bool public burnEnabled = false;
    uint256 public burnFeePercentage = 1; 

    event TokenSet(address tokenAddress);
    event BurnEnabledUpdated(bool enabled);
    event BurnFeePercentageUpdated(uint256 percentage);
    event FeeBurned(uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setDeflationaryToken(address _tokenAddress) external onlyOwner {
        furnaceToken = IFurnace(_tokenAddress);
        emit TokenSet(_tokenAddress);
    }

    function setBurnEnabled(bool _enabled) external onlyOwner {
        burnEnabled = _enabled;
        emit BurnEnabledUpdated(_enabled);
    }

    function setBurnFeePercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 5, "Burn fee cannot exceed 5%");
        burnFeePercentage = _percentage;
        emit BurnFeePercentageUpdated(_percentage);
    }

    function transferWithFeeBurn(address to, uint256 amount) external {
        require(address(furnaceToken) != address(0), "Furnace token not set");
        require(burnEnabled, "Token burn is not enabled");

        uint256 burnAmount = (amount * burnFeePercentage) / 100;
        uint256 transferAmount = amount - burnAmount;


        furnaceToken.burn(burnAmount);
        emit FeeBurned(burnAmount);


        require(furnaceToken.transfer(to, transferAmount), "Transfer failed");
    }

    function rescueLostToken(address _token, address to, uint256 amount) external onlyOwner {
        require(_token != address(furnaceToken), "Cannot rescue Furnace token");
        IFurnace(_token).transfer(to, amount);
    }
    
    
}