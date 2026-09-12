/*
First experimental implementation of Gambling & Staking powered by DN404 technology 
https://twitter.com/C4SH404
https://c4sh-404.gitbook.io/c4sh-404/
*/
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
    function ownerOf(uint256 tokenId) external view returns (address owner);
}

contract C4SHStaking {
    address public nftTokenAddress;
    address public owner;
    mapping(uint256 => address) public stakedBy; 
    mapping(address => uint256[]) public stakedTokens; 

    event Staked(address indexed staker, uint256 tokenId);
    event Unstaked(address indexed staker, uint256 tokenId);
    event NFTTokenAddressSet(address tokenAddress);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the contract owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }


    function setNFTTokenAddress(address _nftTokenAddress) external onlyOwner {
        nftTokenAddress = _nftTokenAddress;
        emit NFTTokenAddressSet(_nftTokenAddress);
    }


    function stake(uint256 tokenId) external {
        require(nftTokenAddress != address(0), "NFT token address not set");
        IERC721(nftTokenAddress).transferFrom(msg.sender, address(this), tokenId);
        stakedBy[tokenId] = msg.sender;
        stakedTokens[msg.sender].push(tokenId);

        emit Staked(msg.sender, tokenId);
    }

    function unstake(uint256 tokenId) external {
        require(stakedBy[tokenId] == msg.sender, "Not the staker of this token");
        require(nftTokenAddress != address(0), "NFT token address not set");


        uint256[] storage tokens = stakedTokens[msg.sender];
        for (uint i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                tokens[i] = tokens[tokens.length - 1];
                tokens.pop();
                break;
            }
        }

        delete stakedBy[tokenId];
        IERC721(nftTokenAddress).transferFrom(address(this), msg.sender, tokenId);

        emit Unstaked(msg.sender, tokenId);
    }

 
    function viewStakedTokens(address user) external view returns (uint256[] memory) {
        return stakedTokens[user];
    }
}