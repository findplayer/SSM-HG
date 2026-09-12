/**
 *Submitted for verification at Etherscan.io on 2023-04-07
 */

// SPDX-License-Identifier: MIT

/*
     _____                .____    .__             .__    .___   .__
    /  _  \ ______   ____ |    |   |__| ________ __|__| __| _/   |__| ____
   /  /_\  \\____ \_/ __ \|    |   |  |/ ____/  |  \  |/ __ |    |  |/  _ \
  /    |    \  |_> >  ___/|    |___|  < <_|  |  |  /  / /_/ |    |  (  <_> )
  \____|__  /   __/ \___  >_______ \__|\__   |____/|__\____ | /\ |__|\____/
          \/|__|        \/        \/      |__|             \/ \/

          Swap a Legend for an Invader. Supplies are limited. Go fack.
*/

pragma solidity ^0.8.0;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function approve(address to, uint256 tokenId) external;

    function getApproved(
        uint256 tokenId
    ) external view returns (address operator);

    function tokenOfOwnerByIndex(
        address owner,
        uint256 index
    ) external view returns (uint256 tokenId);
}

contract ERC721Holder is IERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) public pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

contract Ownable {
    address public owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}

contract TokenSwap is ERC721Holder, Ownable {
    // Addresses
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address public Legends = 0x372405A6d95628Ad14518BfE05165D397f43dE1D;
    address public Invaders = 0x2f3A9adc5301600Cd9205eF7657cF0733fF71D04;
    address public Titans = 0x21d6Fe3B109808Fc69CDaF9829457B0d780Bd975;

    constructor() {}

    function pullInvader() private {
        // Get the next available Invaders NFT to be swapped
        uint256 nextTokenId = IERC721(Invaders).tokenOfOwnerByIndex(address(this), 0);

        // Transfer the selected Invaders NFT to the caller
        IERC721(Invaders).safeTransferFrom(address(this), msg.sender, nextTokenId);
    }

    function sendToken(uint256 tokenId) private {
        // Create an instance of the ERC-721 token contract
        IERC721 tokenContract = IERC721(Invaders);

        // Call the safeTransferFrom function of the ERC-721 token contract to transfer the token
        tokenContract.safeTransferFrom(address(this), msg.sender, tokenId);
    }    

    function ownsTitan() public view returns (bool) {
        IERC721 tokenContract = IERC721(Titans);
        uint256 ownedTitans = tokenContract.balanceOf(msg.sender);
        if (ownedTitans > 0) {
            return true;
        }
        return false;
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

    function legendSwap(uint256 _legendTokenId) external {
        require(ownsTitan(), "You do not own a Titan, you naughty degen");

        // Check if the caller is the owner of the Legend NFT
        require(
            IERC721(Legends).ownerOf(_legendTokenId) == msg.sender,
            "You must own the Legend being burned"
        );

        // Get the balance of Invaders NFTs held by the contract
        uint256 contractBalance = IERC721(Invaders).balanceOf(address(this));
        require(contractBalance > 0, "Contract has no tokens");

        // Burn the Legend NFT by transferring it to the dead address
        sendNFTToDead(Legends, _legendTokenId);

        pullInvader();
    }
}