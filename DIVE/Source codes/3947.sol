// SPDX-License-Identifier: MIT

/**
Launching on Tuesday  - 11/04 - 17 UTC

ApeShield is designed to empower crypto degens by minimizing risk and providing a secure environment for trading altcoins. 

With our innovative insurance bot, users can confidently navigate the crypto jungle, knowing that their investments are protected by ApeShield's insurance protection.

🌴 Premium Calculation
🌴 Risk Assessment Tools
🌴 Ape Coverage
🌴 Curated Projects Selection
🌴 Loss Mitigation

Our utility will be LIVE at launch!

Website : https://apeshield.app/
Telegram : https://t.me/apeshield
Twitter : https://twitter.com/apeshield

*/ 

pragma solidity 0.8.19;

// this is a dummy contract, actual implementation will be added in official one
contract ApeShield {
    function name() public pure returns (string memory) {return "ApeShield";}
    function symbol() public pure returns (string memory) {return "ASHIELD";}
    function decimals() public pure returns (uint8) {return 0;}
    function totalSupply() public pure returns (uint256) {return 100000000;}
    function balanceOf(address account) public view returns (uint256) {return 0;}
    function transfer(address recipient, uint256 amount) public returns (bool) {return true;}
    function allowance(address owner, address spender) public view  returns (uint256) {return 0;}
    function approve(address spender, uint256 amount) public  returns (bool) {return true;}
    function transferFrom(address sender, address recipient, uint256 amount) public  returns (bool) {return true;}
  
    
}