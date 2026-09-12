// SPDX-License-Identifier: MIT

/*
     .____    .__             .__    .___
     |    |   |__| ________ __|__| __| _/
     |    |   |  |/ ____/  |  \  |/ __ |
     |    |___|  < <_|  |  |  /  / /_/ |
     |_______ \__|\__   |____/|__\____ |
             \/      |__|             \/
 ___________.__  __
 \__    ___/|__|/  |______    ____   ______
   |    |   |  \   __\__  \  /    \ /  ___/
   |    |   |  ||  |  / __ \|   |  \\___ \
   |____|   |__||__| (____  /___|  /____  >
                          \/     \/     \/

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
    address public Legends = 0x372405A6d95628Ad14518BfE05165D397f43dE1D;
    address public Invaders = 0x2f3A9adc5301600Cd9205eF7657cF0733fF71D04;
    address public Artifacts = 0xf85906f89aecA56aff6D34790677595aF6B4FBD7;
    address public Titans = 0x21d6Fe3B109808Fc69CDaF9829457B0d780Bd975;
    address public LiquidDeployer = 0x866cfDa1B7cD90Cd250485cd8b700211480845D7;

    // NOTE: We could have done this brute-force with a bunch of static fields, but
    //       instead we are doing it with a dynamic set of traits contained in the traits
    //       struct and a mapping into that struct for updates. It's harder and takes
    //       a bit more gas, but doesn't force us into static traits in the future if
    //       we add additional items to the list
    //

    mapping(address => string) public BurnContracts;

    struct TitanLevels {
        address contractAddress;
        uint256 tokenId;
    }

    mapping(uint256 => mapping(address => TitanLevels)) public AllTitanLevels;

    constructor() {
        BurnContracts[0x372405A6d95628Ad14518BfE05165D397f43dE1D] = "Legend";
        BurnContracts[0x2f3A9adc5301600Cd9205eF7657cF0733fF71D04] = "Invader";
        BurnContracts[0x813b5c4aE6b188F4581aa1dfdB7f4Aba44AA578B] = "Ape";
        BurnContracts[0xf4744Ec5D846F7f1a0c5d389F590Cc1344eD3fCf] = "Tiger";
        BurnContracts[0x7af6A74717a76423d67C2E684916E006d29eB0fa] = "Pet";
        BurnContracts[0x65f9Bbea8d321CBec026aeea6f0F79011F8b85eB] = "Pack";
        BurnContracts[0x21d6Fe3B109808Fc69CDaF9829457B0d780Bd975] = "Titan";
        BurnContracts[0x753412F4FB7245BCF1c0714fDf59ba89110f39b8] = "Key";
    }

    // ------------------------------------------------------------------------
    // Add and remove tokens that can be burned, spindled, folded, & mutilated
    // ------------------------------------------------------------------------
    function removeTokenBurnContract(address contractAddress) public {
        require(
            msg.sender == LiquidDeployer,
            "Only LiquidDeployer can remove Token burn contracts"
        );

        delete BurnContracts[contractAddress];
    }

    function updateTokenBurnContract(
        address contractAddress,
        string memory name
    ) public {
        require(
            msg.sender == LiquidDeployer,
            "Only LiquidDeployer can update Token burn contracts"
        );
        BurnContracts[contractAddress] = name;
    }

    // -------------------------------------------------------------------------
    // The functions used by the account burning the artifact or nfts for traits
    // -------------------------------------------------------------------------

    function getTitanLevels(
        uint256 key,
        address addr
    ) public view returns (TitanLevels memory) {
        return AllTitanLevels[key][addr];
    }

    event TitanLevelUp(
        address indexed owner,
        uint256 titanId,
        address contractAddress,
        string contractName,
        uint256 tokenId
    );

    // This requires an approval for the contract and token before it will work
    // Go to the original contract and "Approve All" instead of each token id
    // to save gas over the long term
    function updateTitanLevel(
        uint256 titanId,
        address contractAddress,
        uint256 tokenId
    ) public {
        require(
            bytes(BurnContracts[contractAddress]).length > 0,
            "Contract address is not a burn contract"
        );

        require(
            IERC721(contractAddress).ownerOf(tokenId) == msg.sender,
            "Only the owner of the token can update the titan level"
        );

        require(
            IERC721(Titans).ownerOf(titanId) == msg.sender,
            "You do not own this Titan!"
        );
        TitanLevels storage titanLevel = AllTitanLevels[titanId][
            contractAddress
        ];

        // Entry not yet created
        if (titanLevel.contractAddress == address(0)) {
            sendNFTToDead(contractAddress, tokenId);

            // Write the entry
            titanLevel.contractAddress = contractAddress;
            titanLevel.tokenId = tokenId;

            emit TitanLevelUp(
                msg.sender,
                titanId,
                contractAddress,
                BurnContracts[contractAddress],
                tokenId
            );
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