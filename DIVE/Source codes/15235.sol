// File: @openzeppelin/contracts/utils/introspection/IERC165.sol


// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.0;

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

// File: @openzeppelin/contracts/token/ERC721/IERC721.sol


// OpenZeppelin Contracts (last updated v4.8.0) (token/ERC721/IERC721.sol)

pragma solidity ^0.8.0;


/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC721
     * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
     * understand this adds an external call which potentially creates a reentrancy vulnerability.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);
}

// File: contracts/SlimysClaim.sol



pragma solidity ^0.8.9;




interface IERC721A is IERC721 {

    function walletOfOwner(address owner) external view returns(uint256[] memory);

    function balanceOf(address owner) external view returns (uint256);

    function ownerOf(uint256 tokenId) external view returns (address owner);
}



contract SlimysClaim {

    
    mapping(address => uint256[]) public holders;
    bool public invalidIdClaimed = false;
    address public owner; 
    address public deadWallet = 0x000000000000000000000000000000000000dEaD;
    IERC721A public v1;
    IERC721A public v2;
    

    modifier onlyOwner {
        require (msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _v1, address _v2){
        owner = msg.sender;
        v1 = IERC721A(_v1);
        v2 = IERC721A(_v2);

        
    } 
    function onERC721Received(
    address, 
    address, 
    uint256, 
    bytes calldata
)external returns(bytes4) {
    return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
} 

    


    function getV1TokenIds(address _addr) public view returns (uint256 [] memory) {
        return v1.walletOfOwner(_addr);
    } 

    function invalidIdClaim() external {
        if(!invalidIdClaimed){
            if(v1.ownerOf(0) == msg.sender){
           v1.transferFrom(msg.sender, deadWallet, 0);
           v2.transferFrom(address(this), msg.sender, 44);

           invalidIdClaimed = true;
           } else {
               revert("Id lookup failed.");
           }
        } else {
            revert("Invalid Id already claimed.");
        }
        
        
    }

    function claim() external {


           uint256[] memory ids = getV1TokenIds(msg.sender);
               
               for(uint8 i = 0; i < ids.length; i++){
                   //*********Caution: the V1 transfer requires an approval step
                   v1.transferFrom(msg.sender, deadWallet, ids[i]);
                   //********************************************************//
                   v2.transferFrom(address(this), msg.sender, ids[i]);
                   }
               
          
    }




    function airdrop(address _addr, uint256[] calldata _ids) external onlyOwner{
        for(uint8 i; i < _ids.length; i++){
            v2.transferFrom(address(this), _addr, _ids[i]);
        }
    }

    function multiAirdrop(address[] calldata _addr) external onlyOwner{
        for(uint8 i; i < _addr.length; i++){
            uint256[] memory ids = getV1TokenIds(_addr[i]);
            for(uint8 j; j < ids.length; j++){
                v2.transferFrom(address(this), _addr[i], ids[j]);
            }
        }
    }


    function withdrawUnclaimed(uint256[] calldata _ids) external onlyOwner {
        for(uint8 i; i < _ids.length; i++){
            v2.transferFrom(address(this), owner, _ids[i]);
        }
    }

    function setVersions(address _v1, address _v2) external onlyOwner{
        v1 = IERC721A(_v1);
        v2 = IERC721A(_v2);
    }
}