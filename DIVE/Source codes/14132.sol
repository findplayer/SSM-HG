// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721 {
    function transferFrom(address from, address to, uint tokenId) external;
}

contract CFWMarketDelegate {
    address public owner; 
    struct Listing {
        address nftAddress;
        uint tokenId;
        address seller;
        uint price;
        bool isActive;
    }
    uint public nextListingId;
    mapping(uint => Listing) public listings;

    event Listed(uint listingId, address seller, address nftAddress, uint tokenId, uint price);
    event Bought(uint listingId, address buyer, uint price);

    constructor() {
        owner = 0x2d62B7B4aB2aeA16f53f78aF3544088300040126;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    function listNFT(address _nftAddress, uint _tokenId, uint _price) external returns (uint listingId) {
        require(_price > 0, "Price must be greater than 0");

        listingId = nextListingId++;
        listings[listingId] = Listing({
            nftAddress: _nftAddress,
            tokenId: _tokenId,
            seller: msg.sender,
            price: _price,
            isActive: true
        });

        emit Listed(listingId, msg.sender, _nftAddress, _tokenId, _price);
    }

    function buyNFT(uint _listingId) external payable {
        Listing storage listing = listings[_listingId];
        require(listing.isActive, "Listing is not active");
        require(msg.value == listing.price, "Incorrect value sent");

        
        listing.isActive = false; 

        payable(listing.seller).transfer(msg.value); 
        emit Bought(_listingId, msg.sender, msg.value);
    }


    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }


    function _transferNFT(address _from, address _to, address _nftAddress, uint _tokenId) internal {
 
    }
}