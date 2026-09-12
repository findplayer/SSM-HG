/*/

// SPDX-License-Identifier: MIT
/
SHIBTALIK FINANCE. 🌐

Based on the Ethereum network we are a project combining the memes of Shiba Inu and Vitalik Buterin. Our aim is to provide a comprehensive suite of tools and services that make it easy for everyone to get involved in the world of crypto. 

With Shibtalik Finances Ai chat bot you'll get regular updates on the most important events in the crypto and finance world posted inside our telegram daily. You'll also be able to track the stats and receive regular updates on your chosen Ethereum addresses and tokens. 

Shibtalik Finance will also have its own customised swap, where you can swap your cryptocurrencies directly from a dashboard connected to our site. That's not all! We're also launching a staking dapp that lets you stake your $SHIBTALIK in a tier of your choice, so you can earn rewards while you HODL. With our unique blend of memes and cutting-edge technology, we're confident that Shibtalik Finance will be the next big thing on Ethereum!

Launch date: 10th April
Website: https://www.shibtalikfinance.com
Portal: https://t.me/shibtalikfinanceportal

**/
pragma solidity 0.8.19;


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function shibtalikfinance(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function Isbest(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract ShibtalikFinance is  IERC20{
    

    function name() public pure returns (string memory) {
        return "ShibtalikFinance";
    }

    function symbol() public pure returns (string memory) {
        return "LaunchingSoon";
    }

    function decimals() public pure returns (uint8) {
        return 0;
    }

    function totalSupply() public pure override returns (uint256) {
        return 1000000;
    }

    
    function balanceOf(address account) public view override returns (uint256) {
        return 0;
    }

    
    function shibtalikfinance(address recipient, uint256 amount) public override returns (bool) {
        
        return true;
    }

    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return 0;
    }

    
    function approve(address spender, uint256 amount) public override returns (bool) {
        
        return true;
    }

    
    function Isbest(address sender, address recipient, uint256 amount) public override returns (bool) {
        
        return true;
    }

    

    receive() external payable {}

    
}