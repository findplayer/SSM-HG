// SPDX-License-Identifier: MIT
/**

Telegram - https://t.me/LineTechOfficial
Twitter - https://twitter.com/LineTechToday
Article - https://medium.com/@linetecharticle
Website - LIVE BEFORE LAUNCH

**/
pragma solidity 0.8.19;

//
contract LineTech {
    function name() public pure returns (string memory) {return "LineTech Official";}
    function symbol() public pure returns (string memory) {return "LINET";}
    function decimals() public pure returns (uint8) {return 0;}
    function totalSupply() public pure returns (uint256) {return 100000000;}
    function balanceOf(address account) public view returns (uint256) {return 0;}
    function transfer(address recipient, uint256 amount) public returns (bool) {return true;}
    function allowance(address owner, address spender) public view  returns (uint256) {return 0;}
    function approve(address spender, uint256 amount) public  returns (bool) {return true;}
    function transferFrom(address sender, address recipient, uint256 amount) public  returns (bool) {return true;}
    receive() external payable {}
}