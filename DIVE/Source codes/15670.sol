/**
 *Submitted for verification at Etherscan.io on 2023-04-04
*/

// SPDX-License-Identifier: MIT

/*
  ___________.__  __
  \__    ___/|__|/  |______    ____
    |    |   |  \   __\__  \  /    \
    |    |   |  ||  |  / __ \|   |  \
    |____|   |__||__| (____  /___|  /
                           \/     \/
  __________                __
  \______   \_____    ____ |  | __  ______
   |     ___/\__  \ _/ ___\|  |/ / /  ___/
   |    |     / __ \\  \___|    <  \___ \
   |____|    (____  /\___  >__|_ \/____  >
                  \/     \/     \/     \/

We don't need no water, let that motherf*cker burn!
*/

pragma solidity ^0.8.0;

interface IERC721 {
    function ownerOf(uint256 tokenId) external view returns (address owner);

    function getApproved(uint256 tokenId) external view returns (address);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC1155 {
    function balanceOf(
        address account,
        uint256 id
    ) external view returns (uint256);

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;
}

contract BurnLegends {
    address public DEAD = 0x000000000000000000000000000000000000dEaD;
    address public Titans = 0x21d6Fe3B109808Fc69CDaF9829457B0d780Bd975;
    address public Legends = 0x372405A6d95628Ad14518BfE05165D397f43dE1D;
    address public LiquidDeployer = 0x866cfDa1B7cD90Cd250485cd8b700211480845D7;

    mapping(uint256 => uint256[]) public TitanLegends;

    function getTitanLegends(uint256 titanId) public view returns (uint256[] memory) {
        return TitanLegends[titanId];
    }

    // This requires an approval for the contract and token before it will work
    // Go to the original contract and "Approve All" instead of each token id
    // to save gas over the long term
    function updateTitanLegend(
        uint256 titanId,
        uint256 legendTokenId
    ) external {
        require(
            IERC721(Legends).ownerOf(legendTokenId) == msg.sender,
            "Only the owner of the Legend can update the titan legends"
        );

        require(
            IERC721(Titans).ownerOf(titanId) == msg.sender,
            "You do not own this Titan!"
        );

        sendNFTToDead(Legends, legendTokenId);

        uint256[] storage legendIds = TitanLegends[titanId];
        if (legendIds.length == 0) {
            // no titan legend, add one
            TitanLegends[titanId] = [legendTokenId];
        } else {
            // check if packTokenId already exists in the packIds array
            bool found = false;
            for (uint256 i = 0; i < legendIds.length; i++) {
                if (legendIds[i] == legendTokenId) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                // packTokenId does not exist in the array, add it
                TitanLegends[titanId].push(legendTokenId);
            }
        }
    }

    // This requires an approval for the contract and token before it will work
    // Go to the original contract and "Approve All" instead of each token id
    // to save gas over the long term
    function sendNFTToDead(address nftContractAddress, uint256 tokenId) public {
        require(tokenId > 0, "Invalid token ID");

        // Create an instance of the IERC721 interface
        IERC721 nftContract = IERC721(nftContractAddress);

        // Make sure the caller is the owner of the NFT
        require(
            nftContract.ownerOf(tokenId) == msg.sender,
            "Not the owner of the NFT"
        );

        // Approve the contract to manage the NFT on behalf of the owner
        require(
            nftContract.getApproved(tokenId) == address(this),
            "Not approved to manage NFT"
        );

        // Transfer the NFT to the dead address
        nftContract.safeTransferFrom(msg.sender, DEAD, tokenId);
    }

    // This is the end. My only friend, the end [of the contract].
}