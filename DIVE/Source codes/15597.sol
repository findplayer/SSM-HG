// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.4;

interface IERC6551 {
    function assignOwnershipTransitionPrice(address walletAddress, uint256 price) external;
    function executeOwnershipTransition(address from, address to, uint256 price) external;
}

contract ERC6551WalletOwnership is IERC6551 {
    event AssignPrice(address indexed walletAddress, uint256 indexed price);
    event OwnershipTransition(address indexed previousOwner, address indexed newOwner, uint256 price);

    mapping(address => uint256) private walletTransitionPrices;

    function assignOwnershipTransitionPrice(address walletAddress, uint256 price) override external {
        walletTransitionPrices[walletAddress] = price;
        emit AssignPrice(walletAddress, price);
    }

    function executeOwnershipTransition(address from, address to, uint256 price) override external {
        require(walletTransitionPrices[from] > 0, "Transition not permitted.");
        require(walletTransitionPrices[from] <= price, "Price too low.");
        delete walletTransitionPrices[from];
        emit OwnershipTransition(from, to, price);
    }

    function checkTransitionPrice(address walletAddress) public view returns (uint256) {
        return walletTransitionPrices[walletAddress];
    }
}