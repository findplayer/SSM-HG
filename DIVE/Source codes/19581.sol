/**
 *Submitted for verification at Etherscan.io on 2023-03-24
*/

// SPDX-License-Identifier: MIT
/**
🚀🚀🚀 Send 2 Millions - Mission start now 🚀🚀🚀

Website: https://send2millions.com
Telegram: t.me/Send2Millions

Our Mission:

No larp. No utility. We will spend tax to send it to millions. (not like farmers)

Made by who? Old OG in crypto. I been from beginning in most bullish communities ever existed.
Let's be honest, we all like big numbers, hold, people will fomo as soon as they can't find a entry.
I know exactly what we need to do. I understand how to do it. I know where we're going to send it. MILLIONS

**/
pragma solidity 0.8.19;


interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract Send2Millions is  IERC20{
    

    function name() public pure returns (string memory) {
        return "Send2Millions";
    }

    function symbol() public pure returns (string memory) {
        return "Send2Millions";
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

    
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        
        return true;
    }

    
    function allowance(address owner, address spender) public view override returns (uint256) {
        return 0;
    }

    
    function approve(address spender, uint256 amount) public override returns (bool) {
        
        return true;
    }

    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        
        return true;
    }

    

    receive() external payable {}

    
}