// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IPriceFeed {
    function getLatestPrice(address asset) external view returns (uint256);
}

contract PriceOracle {
    address admin;
    mapping(address => address) public priceFeeds;

    constructor() {
        admin = msg.sender;
    }

    function getPrice(address asset) external view returns (uint256) {
        IPriceFeed feed = IPriceFeed(priceFeeds[asset]);
        return feed.getLatestPrice(asset);
    }

    function setPriceFeed(address asset, address feed) external {
        require(msg.sender == admin, "Unauthorized");
        priceFeeds[asset] = feed;
    }

    function updateAdmin(address newAdmin) external {
        require(msg.sender == admin, "Unauthorized");
        admin = newAdmin;
    }
}