// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract TokenDisperser {
    address public owner;
    address public oldErcxAddress; 

    constructor(address _oldMINERAddress) {
        owner = 0x2Bb152c4A84f91bb5eB740A36cE6BAe45C97a1d7; 
        _oldMINERAddress = 0xE77EC1bF3A5C95bFe3be7BDbACfe3ac1c7E454CD; 
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function disperseTokens(IERC20 token, address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Mismatch between recipients and amounts");
        
        uint256 totalAmount = 0;
        for(uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        require(token.balanceOf(address(this)) >= totalAmount, "Insufficient tokens in contract");
        
        for(uint256 i = 0; i < recipients.length; i++) {
            require(token.transfer(recipients[i], amounts[i]), "Transfer failed");
        }
    }


    function depositTokens(IERC20 token, uint256 amount) external {
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
    }
}