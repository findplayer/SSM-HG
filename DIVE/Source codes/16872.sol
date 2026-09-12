// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV2Router {
    function WETH() external pure returns (address);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract DwagonBuy {
    address public dwagon;
    address public owner;
    IUniswapV2Router public uniswapRouter;

    constructor(address _owner, address _dwagon, address _uniswapRouter) {
        owner = _owner;
        dwagon = _dwagon;
        uniswapRouter = IUniswapV2Router(_uniswapRouter);
    }

    receive() external payable {}
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner allowed");
        _;
    }

    function buyDwagons() external onlyOwner {
        uint256 ethBal = address(this).balance;
        require(ethBal != 0, "ETH != 0");

        uint256 ownerFee = ethBal / 2;
        uint256 amountTobeSwapped = ethBal - ownerFee;

        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = dwagon;

        // swap tokens
        uniswapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: amountTobeSwapped
        }(0, path, owner, block.timestamp + 1800);
    }

    function withdrawStuckFunds(uint256 amountInWei) external onlyOwner {
        payable(msg.sender).transfer(amountInWei);
    }

    function updateDwagonAddress(address newDwagon) external onlyOwner {
        dwagon = newDwagon;
    }
}