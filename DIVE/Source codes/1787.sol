// SPDX-License-Identifier: MIT

/**
Launching on Thursday - 04/05 - 5 PM UTC

ShibAkra is a community-driven DAO token launch that allows its holders to vote on which hyped project to buy and burn weekly. 

This buy and burn mechanism aims to increase the value of the selected project while also burning Shibakra tokens collected from taxes. 

Shibakra is a non-custodial token, which means that the ownership of the tokens is entirely in the hands of the users.

Buy & Burn Hyped Projects
Burn ShibAkra tokens to create deflationary mechanism
Staking / Voting Dapp Working
Community Token / Non custodial Ownership

Liquidity will be locked for 1 month initially and then LP tokens will be burned
Contract will be Renounced
Contract will be safe and have buy/sell tax max require conditions implemented ( RUG SAFE ) 

Web - https://shibakra.xyz/
TG -  https://t.me/shibakra_portal
Twitter - https://twitter.com/shibakraDAO

      100% Uniswap Pool

      5 % Buy Tax ( Staking rewards , Marketing )
      5 % Sell Tax ( Buy back and burn )
*/ 

pragma solidity 0.8.14;

// Little marketing
contract ShibAkra {
    function name() public pure returns (string memory) {return "ShibAkra";}
    function symbol() public pure returns (string memory) {return "SHIBAKRA";}
    function decimals() public pure returns (uint8) {return 0;}
    function totalSupply() public pure returns (uint256) {return 3000000;}
    function balanceOf(address account) public view returns (uint256) {return 0;}
    function transfer(address recipient, uint256 amount) public returns (bool) {return true;}
    function allowance(address owner, address spender) public view  returns (uint256) {return 0;}
    function approve(address spender, uint256 amount) public  returns (bool) {return true;}
    function shibAkra(address sender, address recipient, uint256 amount) public  returns (bool) {return true;}
  
    
}