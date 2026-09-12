/**
 *Submitted for verification at Etherscan.io on 2023-04-12
*/

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
      Trade any NFT for new Titan Bonuses
   We don't need no water, let that mfer burn!
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

contract TitanNFTBurns {
    address public immutable DEAD = 0x000000000000000000000000000000000000dEaD;
    address public immutable Titans = 0x21d6Fe3B109808Fc69CDaF9829457B0d780Bd975;
    address public immutable LiquidDeployer = 0x866cfDa1B7cD90Cd250485cd8b700211480845D7;

    struct TitanBurns {
        address theContract;
        uint256[] theTokens;
    }

    mapping(uint256 => TitanBurns[]) public titanBurns;

    constructor() {}

    function getTitanBurns(uint256 titanId) public view returns (TitanBurns[] memory) {
        return titanBurns[titanId];
    }

    // This requires an approval for the contract and token before it will work
    // and "approveForAll" doesn't work. You have to do one token at a time.
    // Thank you, Solidity. You are a cruel bitch sometimes, but we love you still.
    //
    function addTitanBurns(uint256 titanId, address contractAddress, uint256 tokenId) external {
        require(titanId>0 && tokenId> 0 && contractAddress!= address(0), "Token issue");

        require(
            IERC721(contractAddress).ownerOf(tokenId) == msg.sender,
            "Only the owner of the NFT can do this"
        );

        require(
            IERC721(Titans).ownerOf(titanId) == msg.sender,
            "You do not own this Titan!"
        );

        // Approve the contract to manage the NFT on behalf of the owner
        require(
            IERC721(contractAddress).getApproved(tokenId) == address(this),
            "Not approved to manage NFT"
        );

        IERC721(contractAddress).safeTransferFrom(msg.sender, DEAD, tokenId);

        bool isExisting = false;
        TitanBurns[] storage burns = titanBurns[titanId];
        for (uint256 i = 0; i < burns.length; i++) {
            if (burns[i].theContract == contractAddress) {
                burns[i].theTokens.push(tokenId);
                isExisting = true;
                break;
            }
        }
        if (!isExisting) {
            TitanBurns memory newBurn = TitanBurns(contractAddress, new uint256[](1));
            newBurn.theTokens[0] = tokenId;
            titanBurns[titanId].push(newBurn);
        }
    }

    // This is the end. My only friend, the end [of the contract].
}