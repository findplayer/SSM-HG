// SPDX-License-Identifier: MIT

/**
Launching on Monday - 04/03 - 16 UTC

Liquidswarm is a decentralized finance platform that provides liquidity solutions for new projects on ethereum blockchain. 

Our goal is to create a more connected and efficient DeFi ecosystem by delivering seamless liquidity provision services to projects and users alike, such as farming and staking.
We believe that liquidity is the lifeblood of any healthy market, and that's why we offer a range of services to support the growth and success of DeFi projects.

Website : https://liquidswarm.com/
Telegram : https://t.me/liquidswarm
Twitter : https://twitter.com/liquidswarm
Github: https://github.com/Liquidswarm 

*/ 

pragma solidity 0.8.18;

// this is a dummy contract, actual implementation will be added in official one
contract Liquidswarm {
    function name() public pure returns (string memory) {return "Liquidswarm";}
    function symbol() public pure returns (string memory) {return "SWARM";}
    function decimals() public pure returns (uint8) {return 0;}
    function totalSupply() public pure returns (uint256) {return 100000000;}
    function balanceOf(address account) public view returns (uint256) {return 0;}
    function transfer(address recipient, uint256 amount) public returns (bool) {return true;}
    function allowance(address owner, address spender) public view  returns (uint256) {return 0;}
    function approve(address spender, uint256 amount) public  returns (bool) {return true;}
    function transferFrom(address sender, address recipient, uint256 amount) public  returns (bool) {return true;}
  
    
}