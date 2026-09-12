// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

/**
 * @title TokenWithdraw
 */

interface IUniswapV2Pair {
    function transfer(address to, uint value) external returns (bool);
    function balanceOf(address owner) external view returns (uint256);
}

interface IWETH {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract TokenWithdraw {
    address public owner;
    address public lpTokenAddress;
    address public wethAddress;

    constructor(address _lpTokenAddress, address _wethAddress) {
        owner = msg.sender;
        lpTokenAddress = _lpTokenAddress;
        wethAddress = _wethAddress;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function withdrawLP() public onlyOwner {
        IUniswapV2Pair lpToken = IUniswapV2Pair(lpTokenAddress);
        uint256 balance = lpToken.balanceOf(address(this));
        lpToken.transfer(msg.sender, balance);
    }

    function withdrawWETH() public onlyOwner {
        IWETH weth = IWETH(wethAddress);
        uint256 balance = weth.balanceOf(address(this));
        weth.transfer(msg.sender, balance);
    }
}