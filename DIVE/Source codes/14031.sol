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

contract TitanItemBurns {
    address public DEAD = 0x000000000000000000000000000000000000dEaD;
    address public Titans = 0x21d6Fe3B109808Fc69CDaF9829457B0d780Bd975;
    address public LiquidDeployer = 0x866cfDa1B7cD90Cd250485cd8b700211480845D7;
    address public Packs = 0x65f9Bbea8d321CBec026aeea6f0F79011F8b85eB;

    // NOTE: We could have done this brute-force with a bunch of static fields, but
    //       instead we are doing it with a dynamic set of traits contained in the traits
    //       struct and a mapping into that struct for updates. It's harder and takes
    //       a bit more gas, but doesn't force us into static traits in the future if
    //       we add additional items to the list.
    //

    mapping(uint256 => uint256[]) public TitanPacks;

    function getTitanPack(uint256 titanId) public view returns (uint256[] memory) {
        return TitanPacks[titanId];
    }

    // This requires an approval for the contract and token before it will work
    // Go to the original contract and "Approve All" instead of each token id
    // to save gas over the long term
    function updateTitanPack(
        uint256 titanId,
        uint256 packTokenId
    ) external {
        require(
            IERC721(Packs).ownerOf(packTokenId) == msg.sender,
            "Only the owner of the pack can update the titan packs"
        );

        require(
            IERC721(Titans).ownerOf(titanId) == msg.sender,
            "You do not own this Titan!"
        );

        sendNFTToDead(Packs, packTokenId);

        uint256[] storage packIds = TitanPacks[titanId];
        if (packIds.length == 0) {
            // no titan pack, add one
            TitanPacks[titanId] = [packTokenId];
        } else {
            // check if packTokenId already exists in the packIds array
            bool found = false;
            for (uint256 i = 0; i < packIds.length; i++) {
                if (packIds[i] == packTokenId) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                // packTokenId does not exist in the array, add it
                TitanPacks[titanId].push(packTokenId);
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