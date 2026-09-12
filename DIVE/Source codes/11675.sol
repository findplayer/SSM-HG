// Facilitates the buying and selling of CASH404 NFTs within a decentralized market, enhancing liquidity and community engagement.
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICASH404NFT {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address);
}

contract CASH404Market {
    struct Listing {
        address seller;
        uint256 price;
    }

    ICASH404NFT public cash404NFT;
    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event Purchased(uint256 indexed tokenId, address indexed buyer, uint256 price);
    event Unlisted(uint256 indexed tokenId);

    constructor(ICASH404NFT _cash404NFT) {
        cash404NFT = _cash404NFT;
    }

    function list(uint256 tokenId, uint256 price) public {
        require(cash404NFT.ownerOf(tokenId) == msg.sender, "Not the owner");
        require(price > 0, "Price must be greater than 0");

        cash404NFT.transferFrom(msg.sender, address(this), tokenId);
        listings[tokenId] = Listing(msg.sender, price);

        emit Listed(tokenId, msg.sender, price);
    }

    function unlist(uint256 tokenId) public {
        require(listings[tokenId].seller == msg.sender, "Not the seller");
        
        delete listings[tokenId];
        cash404NFT.transferFrom(address(this), msg.sender, tokenId);

        emit Unlisted(tokenId);
    }

    function purchase(uint256 tokenId) public payable {
        Listing storage listing = listings[tokenId];
        require(msg.value == listing.price, "Incorrect price");

        payable(listing.seller).transfer(msg.value); // Send funds to seller
        cash404NFT.transferFrom(address(this), msg.sender, tokenId); // Transfer NFT to buyer
        
        delete listings[tokenId]; // Remove listing

        emit Purchased(tokenId, msg.sender, msg.value);
    }
}