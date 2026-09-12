pragma solidity =0.8.6;

// SPDX-License-Identifier: SimPL-2.0

library Bytes {
    bytes internal constant BASE64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    
    function base64Encode(bytes memory bs) internal pure returns(string memory) {
        uint256 remain = bs.length % 3;
        uint256 length = bs.length / 3 * 4;
        bytes memory result = new bytes(length + (remain != 0 ? 4 : 0) + (3 - remain) % 3);
        
        uint256 i = 0;
        uint256 j = 0;
        while (i < length) {
            result[i++] = BASE64_CHARS[uint8(bs[j] >> 2)];
            result[i++] = BASE64_CHARS[uint8((bs[j] & 0x03) << 4 | bs[j + 1] >> 4)];
            result[i++] = BASE64_CHARS[uint8((bs[j + 1] & 0x0f) << 2 | bs[j + 2] >> 6)];
            result[i++] = BASE64_CHARS[uint8(bs[j + 2] & 0x3f)];
            
            j += 3;
        }
        
        if (remain != 0) {
            result[i++] = BASE64_CHARS[uint8(bs[j] >> 2)];
            
            if (remain == 2) {
                result[i++] = BASE64_CHARS[uint8((bs[j] & 0x03) << 4 | bs[j + 1] >> 4)];
                result[i++] = BASE64_CHARS[uint8((bs[j + 1] & 0x0f) << 2)];
                result[i++] = BASE64_CHARS[0];
                result[i++] = 0x3d;
            } else {
                result[i++] = BASE64_CHARS[uint8((bs[j] & 0x03) << 4)];
                result[i++] = BASE64_CHARS[0];
                result[i++] = BASE64_CHARS[0];
                result[i++] = 0x3d;
                result[i++] = 0x3d;
            }
        }
        
        return string(result);
    }
    
    function concat(bytes memory a, bytes memory b)
        internal pure returns(bytes memory) {
        
        return abi.encodePacked(a, b);
    }
}



library String {
    function equals(string memory a, string memory b)
        internal pure returns(bool) {
        
        bytes memory ba = bytes(a);
        bytes memory bb = bytes(b);
        
        if (ba.length != bb.length) {
            return false;
        }
        
        uint256 length = ba.length;
        
        for (uint256 i = 0; i < length; ++i) {
            if (ba[i] != bb[i]) {
                return false;
            }
        }
        
        return true;
    }
    
    function concat(string memory a, string memory b)
        internal pure returns(string memory) {
        
        return string(abi.encodePacked(a, b));
    }
    
    function utf8length(string memory s) internal pure returns(uint256) {
        bytes memory bs = bytes(s);
        uint256 bytelength = bs.length;
        uint256 length = 0;
        
        for (uint256 i = 0; i < bytelength; ++length) {
            bytes1 b = bs[i];
            
            if (b < 0x80) {
                i += 1;
            } else if (b < 0xE0) {
                i += 2;
            } else if (b < 0xF0) {
                i += 3;
            } else if (b < 0xF8) {
                i += 4;
            } else if (b < 0xFC) {
                i += 5;
            } else {
                i += 6;
            }
        }
        
        return length;
    }
    
    // . for \u2e
    // zero width for \u200b \u200c \u200d and \ufeff
    function checkName(string memory name) internal pure returns(bool) {
        bytes memory bs = bytes(name);
        uint256 bytelength = bs.length - 2;
        
        for (uint256 i = 0; i < bytelength; ++i) {
            bytes1 b = bytes1(bs[i]);
            
            if (b == 0x2e) {
                return false;
            } else if (b == 0xe2) {
                if (bytes1(bs[i + 1]) == 0x80 && (
                    bytes1(bs[i + 2]) == 0x8b ||
                    bytes1(bs[i + 2]) == 0x8c ||
                    bytes1(bs[i + 2]) == 0x8d)
                ) {
                    return false;
                }
            } else if (b == 0xef) {
                if (bytes1(bs[i + 1]) == 0xbb && bytes1(bs[i + 2]) == 0xbf) {
                    return false;
                }
            }
        }
        
        return true;
    }
}





// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

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
        require(newOwner != address(0), "Ownable: new owner is the zero address");
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



abstract contract Controlable is Ownable {
    event ControllerChanged(address indexed controller, bool enabled);
    
    mapping(address => bool) internal controllers;
    
    modifier onlyController {
        require(controllers[msg.sender], "not controller");
        _;
    }
    
    function isController(address controller) external view returns(bool) {
        return controllers[controller];
    }
    
    function setController(address controller, bool enabled)
        external onlyOwner {
        
        controllers[controller] = enabled;
        emit ControllerChanged(controller, enabled);
    }
}


// OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/ERC721Enumerable.sol)

// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/ERC721.sol)

// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/IERC721.sol)

// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

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
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
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
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
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


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/IERC721Receiver.sol)

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
     * The selector can be obtained in Solidity with `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}


// OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/IERC721Metadata.sol)


/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {
    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
}


// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     *
     * [IMPORTANT]
     * ====
     * You shouldn't rely on `isContract` to protect against flash loan attacks!
     *
     * Preventing calls from contracts is highly discouraged. It breaks composability, breaks support for smart wallets
     * like Gnosis Safe, and does not provide security since it can be circumvented by calling from a contract
     * constructor.
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize/address.code.length, which returns 0
        // for contracts in construction, since the code is only stored at the end
        // of the constructor execution.

        return account.code.length > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verifies that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason using the provided one.
     *
     * _Available since v4.3._
     */
    function verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


// OpenZeppelin Contracts v4.4.1 (utils/Strings.sol)

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}


// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)


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
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}



/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. If set, the resulting URI for each
     * token will be the concatenation of the `baseURI` and the `tokenId`. Empty
     * by default, can be overridden in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || isApprovedForAll(owner, spender) || getApproved(tokenId) == spender);
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);

        _afterTokenTransfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer from incorrect owner");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits a {ApprovalForAll} event.
     */
    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}
}


// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC721/extensions/IERC721Enumerable.sol)


/**
 * @title ERC-721 Non-Fungible Token Standard, optional enumeration extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Enumerable is IERC721 {
    /**
     * @dev Returns the total amount of tokens stored by the contract.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns a token ID owned by `owner` at a given `index` of its token list.
     * Use along with {balanceOf} to enumerate all of ``owner``'s tokens.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256);

    /**
     * @dev Returns a token ID at a given `index` of all the tokens stored by the contract.
     * Use along with {totalSupply} to enumerate all tokens.
     */
    function tokenByIndex(uint256 index) external view returns (uint256);
}



/**
 * @dev This implements an optional extension of {ERC721} defined in the EIP that adds
 * enumerability of all the token ids in the contract as well as all token ids owned by each
 * account.
 */
abstract contract ERC721Enumerable is ERC721, IERC721Enumerable {
    // Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(IERC165, ERC721) returns (bool) {
        return interfaceId == type(IERC721Enumerable).interfaceId || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721Enumerable-tokenOfOwnerByIndex}.
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721.balanceOf(owner), "ERC721Enumerable: owner index out of bounds");
        return _ownedTokens[owner][index];
    }

    /**
     * @dev See {IERC721Enumerable-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _allTokens.length;
    }

    /**
     * @dev See {IERC721Enumerable-tokenByIndex}.
     */
    function tokenByIndex(uint256 index) public view virtual override returns (uint256) {
        require(index < ERC721Enumerable.totalSupply(), "ERC721Enumerable: global index out of bounds");
        return _allTokens[index];
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);

        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param to address representing the new owner of the given token ID
     * @param tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        uint256 length = ERC721.balanceOf(to);
        _ownedTokens[to][length] = tokenId;
        _ownedTokensIndex[tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = ERC721.balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}





interface IERC721TokenReceiverEx {
    function onERC721ExReceived(address operator, address from,
        uint256[] memory tokenIds, bytes memory data)
        external returns(bytes4);
}



abstract contract ERC721Ex is ERC721Enumerable, Ownable {
    using Address for address;
    
    string internal __baseURI;
    
    modifier onlyApprovedOrOwner(uint256 tokenId) {
        require(_isApprovedOrOwner(msg.sender, tokenId),
            "not approved");
            
        _;
    }
    
    // [startIndex, endIndex)
    function tokensOf(address owner, uint256 startIndex, uint256 endIndex)
        public view returns(uint256[] memory) {
        
        require(owner != address(0), "owner is zero address");
        
        if (endIndex == 0) {
            endIndex = balanceOf(owner);
        }
        
        uint256[] memory result = new uint256[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; ++i) {
            result[i - startIndex] = tokenOfOwnerByIndex(owner, i);
        }
        
        return result;
    }
    
    function tokensOf(address owner) external view returns(uint256[] memory) {
        return tokensOf(owner, 0, 0);
    }
    
    function safeBatchTransferFrom(address from, address to,
        uint256[] memory tokenIds) external {
        
        safeBatchTransferFrom(from, to, tokenIds, "");
    }
    
    function safeBatchTransferFrom(address from, address to,
        uint256[] memory tokenIds, bytes memory data) public {
        
        batchTransferFrom(from, to, tokenIds);
        
        if (to.isContract()) {
            require(IERC721TokenReceiverEx(to)
                .onERC721ExReceived(msg.sender, from, tokenIds, data)
                == IERC721TokenReceiverEx.onERC721ExReceived.selector,
                "onERC721ExReceived() return invalid");
        }
    }
    
    function batchTransferFrom(address from, address to,
        uint256[] memory tokenIds) public {
        
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            transferFrom(from, to, tokenIds[i]);
        }
    }
    
    function _baseURI() internal view override returns(string memory) {
        return __baseURI;
    }
    
    function setBaseURI(string calldata baseURI) external onlyOwner {
        __baseURI = baseURI;
    }
}







interface IERC897 {
    event ImplementationChanged(address indexed oldImp, address indexed newImp);
    
    function proxyType() external view returns(uint256);
    
    function implementation() external view returns(address);
}


contract ERC897 is Ownable, IERC897 {
    address public override implementation;
    uint256 private _proxyType = 2;
    
    receive() external payable {
    }
    
    fallback(bytes calldata input) external payable returns(bytes memory) {
        (bool success, bytes memory output) = implementation.delegatecall(input);
        
        require(success, string(output));
        
        return output;
    }
    
    function proxyType() external override view returns(uint256) {
        return _proxyType;
    }
    
    function setImplementation(address imp) external onlyOwner {
        emit ImplementationChanged(implementation, imp);
        implementation = imp;
    }
    
	/*
    function callContract(address contractAddress, bytes calldata input)
        external payable onlyOwner {
        
        (bool success, bytes memory output) = contractAddress.call(input);
        
    	require(success, string(output));
    }
    
    function callContract(address contractAddress, bytes calldata input, uint256 value)
        external payable onlyOwner {
        
        (bool success, bytes memory output) = contractAddress.call
            {value: value} (input);
        
        require(success, string(output));
    }
	*/
}




// OpenZeppelin Contracts v4.4.1 (interfaces/IERC165.sol)






interface IENS {
    // Logged when the owner of a node assigns a new owner to a subnode.
    event NewOwner(bytes32 indexed node, bytes32 indexed label, address owner);

    // Logged when the owner of a node transfers ownership to a new account.
    event Transfer(bytes32 indexed node, address owner);

    // Logged when the resolver for a node changes.
    event NewResolver(bytes32 indexed node, address resolver);

    // Logged when the TTL of a node changes
    event NewTTL(bytes32 indexed node, uint64 ttl);

    // Logged when an operator is added or removed.
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external;
    function setSubnodeRecord(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external;
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external returns(bytes32);
    function setResolver(bytes32 node, address resolver) external;
    function setOwner(bytes32 node, address owner) external;
    function setTTL(bytes32 node, uint64 ttl) external;
    function setApprovalForAll(address operator, bool approved) external;
    
    function owner(bytes32 node) external view returns(address);
    function resolver(bytes32 node) external view returns(address);
    function ttl(bytes32 node) external view returns(uint64);
    function recordExists(bytes32 node) external view returns(bool);
    function isApprovedForAll(address owner, address operator) external view returns(bool);
    function isOwnerOrApproval(address operator, bytes32 node) external view returns(bool);
}


abstract contract AbstractResolver is Ownable, IERC165 {
    IENS internal registry;
    
    modifier onlyOwnerOrApproval(bytes32 node) {
        require(registry.isOwnerOrApproval(msg.sender, node),
            "not owner or approval");
            
        _;
    }
    
    function setRegistry(address registryAddr) external onlyOwner {
        registry = IENS(registryAddr);
    }
    
    function supportsInterface(bytes4 interfaceID)
        public override virtual pure returns(bool) {
        
        return interfaceID == IERC165.supportsInterface.selector;
    }
}


contract NameMap is ERC897, AbstractResolver, Controlable {
    struct NameInfo {
        string name;
        address nameOwner;
        
        address regAddress;
        uint256 regTokenId;
        address regOwner;
        uint256 registry;
        uint256 expiry;
        
        address avatarAddress;
        uint256 avatarTokenId;
    }
    
    struct BaseInfo {
        string name;
        
        address regAddress;
        uint256 regTokenId;
    }
    
    struct AvatarInfo {
        address addr;
        uint256 tokenId;
    }
    
    mapping(bytes32 => BaseInfo) baseInfos;
    
    mapping(bytes32 => AvatarInfo) avatarInfos;
    
    function setBaseInfo(bytes32 node, string calldata name,
        address regAddress, uint256 regTokenId)
        external onlyController {
        
        BaseInfo storage baseInfo = baseInfos[node];
        baseInfo.name = name;
        baseInfo.regAddress = regAddress;
        baseInfo.regTokenId = regTokenId;
    }
    
    function setAvatar(bytes32 node, address addr, uint256 tokenId)
        external onlyOwnerOrApproval(node) {
        
        require(IERC721(addr).ownerOf(tokenId) == msg.sender,
            "not the owner");
            
        AvatarInfo storage avatarInfo = avatarInfos[node];
        avatarInfo.addr = addr;
        avatarInfo.tokenId = tokenId;
    }
    
    function getBaseInfo(bytes32 node)
        external view returns(BaseInfo memory) {
        
        return baseInfos[node];
    }
    
    function getNameInfo(bytes32 node)
        public view returns(NameInfo memory) {
        
        BaseInfo storage baseInfo = baseInfos[node];
        
        AvatarInfo storage avatarInfo = avatarInfos[node];
        
        NameInfo memory result = NameInfo({
            name: baseInfo.name,
            nameOwner: registry.owner(node),
            
            regAddress: baseInfo.regAddress,
            regTokenId: baseInfo.regTokenId,
            regOwner: address(0),
            registry: 0,
            expiry: 0,
            
            avatarAddress: avatarInfo.addr,
            avatarTokenId: avatarInfo.tokenId
        });
        
        if (baseInfo.regAddress != address(0)) {
            BaseRegistrar reg = BaseRegistrar(baseInfo.regAddress);
            result.registry = reg.nameRegistries(baseInfo.regTokenId);
            result.expiry = reg.nameExpiries(baseInfo.regTokenId);
            
            bytes memory input = abi.encodeWithSignature(
                "ownerOfSuper(uint256)", baseInfo.regTokenId);
            (bool success, bytes memory output) = baseInfo.regAddress.staticcall(input);
            if (success) {
                (result.regOwner) = abi.decode(output, (address));
            }
        }
        
        return result;
    }
    
    function getNameInfos(bytes32[] calldata nodes)
        external view returns(NameInfo[] memory) {
        
        uint256 length = nodes.length;
        NameInfo[] memory result = new NameInfo[](length);
        
        for (uint256 i = 0; i < length; ++i) {
            result[i] = getNameInfo(nodes[i]);
        }
        
        return result;
    }
}





abstract contract AbstractRegistrar {
    IENS public ens;
    
    bytes32 public baseNode;
    
    constructor(address ensAddr, bytes32 _baseNode) {
        ens = IENS(ensAddr);
        baseNode = _baseNode;
    }
}


contract BaseRegistrar is AbstractRegistrar, ERC721Ex, Controlable {
    using Bytes for bytes;
    using String for string;
    
    event NameMigrated(uint256 indexed id, address indexed owner, uint256 expiries);
    event NameRegistered(uint256 indexed id, address indexed owner, uint256 expiries);
    event NameRenewed(uint256 indexed id, uint256 expiries);
    
    event Nested(uint256 indexed tokenId);
    event Unnested(uint256 indexed tokenId);
    event Expelled(uint256 indexed tokenId);
    
    bytes4 constant private INTERFACE_META_ID = bytes4(keccak256("supportsInterface(bytes4)"));
    bytes4 constant private ERC721_ID = bytes4(
        keccak256("balanceOf(address)") ^
        keccak256("ownerOf(uint256)") ^
        keccak256("approve(address,uint256)") ^
        keccak256("getApproved(uint256)") ^
        keccak256("setApprovalForAll(address,bool)") ^
        keccak256("isApprovedForAll(address,address)") ^
        keccak256("transferFrom(address,address,uint256)") ^
        keccak256("safeTransferFrom(address,address,uint256)") ^
        keccak256("safeTransferFrom(address,address,uint256,bytes)")
    );
    bytes4 constant private RECLAIM_ID = bytes4(keccak256("reclaim(uint256,address)"));
    
    string public baseName;
    
    NameMap nameMap;
    
    // A map of registry times
    mapping(uint256 => uint256) registries;
    
    // A map of expiry times
    mapping(uint256 => uint256) expiries;
    
    uint256 public gracePeriod = 90 days;
    
    mapping(address => bool) public operatorBlackLists;
    
    bool public nestingOpen;
    mapping(uint256 => uint256) private nestingStarted;
    mapping(uint256 => uint256) private nestingTotal;
    bool private nestingTransfer;
    
    constructor(address _ens, bytes32 _baseNode, string memory _baseName,
        string memory _name, string memory _symbol)
        AbstractRegistrar(_ens, _baseNode)
        ERC721(_name, _symbol) {
        
        baseName = _baseName;
        baseNode = _baseNode;
    }

    modifier live {
        require(ens.owner(baseNode) == address(this), "not live");
        _;
    }

    /**
     * @dev Gets the owner of the specified token ID. Names become unowned
     *      when their registration expiries.
     * @param tokenId uint256 ID of the token to query the owner of
     * @return address currently marked as the owner of the given token ID
     */
    function ownerOf(uint256 tokenId) public override view returns(address) {
        require(expiries[tokenId] > block.timestamp, "expired");
        return super.ownerOf(tokenId);
    }
    
    function ownerOfSuper(uint256 tokenId) public view returns(address) {
        return super.ownerOf(tokenId);
    }
    
    function setGracePeriod(uint256 period) external onlyOwner {
        gracePeriod = period;
    }

    // Set the resolver for the TLD this registrar manages.
    function setResolver(address resolver) external onlyOwner {
        ens.setResolver(baseNode, resolver);
    }
    
    function setNameMap(address nm) external onlyOwner {
        nameMap = NameMap(payable(nm));
    }

    // Returns the registration timestamp of the specified id.
    function nameRegistries(uint256 id) external view returns(uint256) {
        return registries[id];
    }

    // Returns the expiration timestamp of the specified id.
    function nameExpiries(uint256 id) external view returns(uint256) {
        return expiries[id];
    }

    // Returns true iff the specified name is available for registration.
    function available(uint256 id) public view returns(bool) {
        // Not available if it's registered here or in its grace period.
        return expiries[id] + gracePeriod < block.timestamp;
    }

    /**
     * @dev Register a name.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     */
    function register(uint256 id, address owner, uint256 duration)
        external returns(uint256) {
        
        return _register(id, owner, duration, true);
    }

    /**
     * @dev Register a name, without modifying the registry.
     * @param id The token ID (keccak256 of the label).
     * @param owner The address that should own the registration.
     * @param duration Duration in seconds for the registration.
     */
    function registerOnly(uint256 id, address owner, uint256 duration) external returns(uint256) {
      return _register(id, owner, duration, false);
    }

    function _register(uint256 id, address owner, uint256 duration, bool updateRegistry)
        internal live onlyController returns(uint256) {
        
        require(available(id), "not available");

        registries[id] = block.timestamp;
        expiries[id] = block.timestamp + duration;
        
        if(_exists(id)) {
            // Name was previously owned, and expired
            _burn(id);
        }
        _mint(owner, id);
        if(updateRegistry) {
            ens.setSubnodeOwner(baseNode, bytes32(id), owner);
        }

        emit NameRegistered(id, owner, block.timestamp + duration);

        return block.timestamp + duration;
    }

    function renew(uint256 id, uint256 duration)
        external live onlyController returns(uint256) {
        
        // Name must be registered here or in grace period
        require(expiries[id] + gracePeriod >= block.timestamp, "expired");

        expiries[id] += duration;
        emit NameRenewed(id, expiries[id]);
        return expiries[id];
    }

    /**
     * @dev Reclaim ownership of a name in ENS, if you own it in the registrar.
     */
    function reclaim(uint256 id, address owner) external live {
        require(_isApprovedOrOwner(msg.sender, id), "not approved or owner");
        ens.setSubnodeOwner(baseNode, bytes32(id), owner);
    }

    function supportsInterface(bytes4 interfaceID)
        public override pure returns(bool) {
        
        return interfaceID == INTERFACE_META_ID ||
               interfaceID == ERC721_ID ||
               interfaceID == RECLAIM_ID;
    }
    
    function setOperatorBlackList(address[] memory addresses, bool enabled)
        external onlyOwner {
        
        for (uint256 i = 0; i < addresses.length; ++i) {
            operatorBlackLists[addresses[i]] = enabled;
        }
    }
    
    function approve(address to, uint256 tokenId) public override {
        require(!operatorBlackLists[to], "in blacklist");
        super.approve(to, tokenId);
    }
    
    function setApprovalForAll(address operator, bool approved)
        public override {
        
        require(!operatorBlackLists[operator], "in blacklist");
        super.setApprovalForAll(operator, approved);
    }
    
    function setNestingOpen(bool open) external onlyOwner {
        nestingOpen = open;
    }
    
    function nestingPeriod(uint256 tokenId)
        external view returns(bool, uint256, uint256){
        
        bool nesting = false;
        uint256 current = 0;
        
        uint256 start = nestingStarted[tokenId];
        if (start != 0) {
            nesting = true;
            current = block.timestamp - start;
        }
        
        uint256 total = current + nestingTotal[tokenId];
        
        return (nesting, current, total);
    }
    
    function toggleNesting(uint256 tokenId)
        public onlyApprovedOrOwner(tokenId) {
        
        uint256 start = nestingStarted[tokenId];
        if (start == 0) {
            require(nestingOpen, "nesting closed");
            nestingStarted[tokenId] = block.timestamp;
            emit Nested(tokenId);
        } else {
            nestingTotal[tokenId] += block.timestamp - start;
            nestingStarted[tokenId] = 0;
            emit Unnested(tokenId);
        }
    }
    
    function toggleNesting(uint256[] calldata tokenIds) external {
        uint256 length = tokenIds.length;
        for (uint256 i = 0; i < length; ++i) {
            toggleNesting(tokenIds[i]);
        }
    }
    
    function expelFromNest(uint256 tokenId) external onlyOwner {
        require(nestingStarted[tokenId] != 0, "not nested");
        nestingTotal[tokenId] += block.timestamp - nestingStarted[tokenId];
        nestingStarted[tokenId] = 0;
        emit Unnested(tokenId);
        emit Expelled(tokenId);
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override {
        require(from == msg.sender || !operatorBlackLists[from],
            "in blacklist");
            
        require(nestingStarted[tokenId] == 0 || nestingTransfer,
            "nesting");
        
        super._beforeTokenTransfer(from, to, tokenId);
    }
    
    function tokenURI(uint256 tokenId)
        public view override returns(string memory) {
        
        require(_exists(tokenId), "nonexistent token");
        
        uint256 registry = registries[tokenId];
        uint256 expiry = expiries[tokenId];
        
        bytes32 node = keccak256(abi.encodePacked(baseNode, tokenId));
        NameMap.BaseInfo memory baseInfo = nameMap.getBaseInfo(node);
        
        bytes memory data = abi.encodePacked(registry, expiry, baseInfo.name);
        
        return _baseURI().concat(data.base64Encode());
    }
}