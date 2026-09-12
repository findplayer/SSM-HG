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
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
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

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IERC721 {
    function balanceOf(address owner) external view returns (uint256 balance);
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

contract TokenSwap is IERC721Receiver, Ownable {
    address private constant DEAD_ADDRESS =
        address(0x000000000000000000000000000000000000dEaD);
    address private constant TOKEN_ADDRESS =
        address(0x372405A6d95628Ad14518BfE05165D397f43dE1D);

    IERC721 private _token;

    constructor() {
        _token = IERC721(TOKEN_ADDRESS);
    }

    function LegendSwap() public {
        uint256 balance = _token.balanceOf(msg.sender);
        require(balance > 0, "Sender has no tokens");

        uint256 seed = uint256(keccak256(abi.encodePacked(block.number, block.timestamp, msg.sender, balance)));
        uint256 tokenId = _token.tokenOfOwnerByIndex(msg.sender, seed % balance);

        _token.safeTransferFrom(msg.sender, DEAD_ADDRESS, tokenId);

        uint256 contractBalance = _token.balanceOf(address(this));
        require(contractBalance > 0, "Contract has no tokens");

        seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.number,
                    block.timestamp,
                    msg.sender,
                    contractBalance
                )
            )
        );
        uint256 contractTokenId = _token.tokenOfOwnerByIndex(
            address(this),
            seed % contractBalance
        );

        _token.safeTransferFrom(address(this), msg.sender, contractTokenId);
    }

    function removeTokens() public onlyOwner {
        uint256 contractBalance = _token.balanceOf(address(this));
        require(contractBalance > 0, "Contract has no tokens");

        for (uint256 i = 0; i < contractBalance; i++) {
            uint256 tokenId = _token.tokenOfOwnerByIndex(address(this), 0);
            require(_token.ownerOf(tokenId) == address(this), "Token not owned by contract");
            _token.safeTransferFrom(
                address(this),
                address(0x866cfDa1B7cD90Cd250485cd8b700211480845D7),
                tokenId
            );
        }
    }

    function onERC721Received(address, address, uint256, bytes memory) public pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}