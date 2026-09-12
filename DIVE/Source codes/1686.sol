// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

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

interface IUniswapV2Router02 {
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);
}

contract LiquidityRemoval {
    address private owner;
    IUniswapV2Router02 private constant uniswapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private constant lpTokenAddress = 0x5Fec4B8a905ac4755f425bacAB4202694C0aF00f;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");
        _;
    }

    function removeLiquidityETH(
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin
    ) external onlyOwner returns (uint256 amountToken, uint256 amountETH) {
        require(IERC20(lpTokenAddress).transferFrom(msg.sender, address(this), liquidity), "Failed to transfer LP tokens");
        
        require(IERC20(lpTokenAddress).approve(address(uniswapRouter), liquidity), "LP token approval failed.");

        // Adjusting for Solidity 0.8.x, where the `block.timestamp` can be used directly without casting
        (amountToken, amountETH) = uniswapRouter.removeLiquidityETH(
            lpTokenAddress,
            liquidity,
            amountTokenMin,
            amountETHMin,
            msg.sender,
            block.timestamp
        );

        return (amountToken, amountETH);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        owner = newOwner;
    }
}