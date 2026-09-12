// https://twitter.com/OHM_ERC404
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract FractionalOwnership {
    struct Fraction {
        uint256 nftId;
        uint256 totalShares;
        mapping(address => uint256) shares;
    }

    mapping(uint256 => Fraction) public fractions;

    function fractionalizeNFT(uint256 nftId, uint256 totalShares) external {
        Fraction storage fraction = fractions[nftId];
        fraction.nftId = nftId;
        fraction.totalShares = totalShares;
        fraction.shares[msg.sender] = totalShares;
    }

    function buyShares(uint256 nftId, uint256 shares) external {
        Fraction storage fraction = fractions[nftId];
        require(fraction.totalShares >= shares, "Not enough shares available");
        fraction.shares[msg.sender] += shares;
        fraction.totalShares -= shares;
    }

    function sellShares(uint256 nftId, uint256 shares) external {
        Fraction storage fraction = fractions[nftId];
        require(fraction.shares[msg.sender] >= shares, "Not enough shares owned");
        fraction.shares[msg.sender] -= shares;
        fraction.totalShares += shares;
    }
}