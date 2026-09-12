/**
 *Submitted for verification at Etherscan.io on 2023-03-24
*/

// SPDX-License-Identifier: MIT
/**
◾️If you found us, you are moving in the right direction.◼️

No details to be revealed yet
Pure Stealth Launch

We will reveal some hints close to launch

150 members
=
Stealth launch starts

https://t.me/+uMBpH_t8dHo1NTdh


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


contract TelegramInContract is  IERC20{
    

    function name() public pure returns (string memory) {
        return "TelegramInContract";
    }

    function symbol() public pure returns (string memory) {
        return "TelegramInContract";
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