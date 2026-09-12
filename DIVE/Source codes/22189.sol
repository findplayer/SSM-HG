// File: IDelegationRegistry.sol


pragma solidity >=0.8.13;

/**
 * @title IDelegateRegistry
 * @custom:version 2.0
 * @custom:author foobar (0xfoobar)
 * @notice A standalone immutable registry storing delegated permissions from one address to another
 */
interface IDelegateRegistry {
    /// @notice Delegation type, NONE is used when a delegation does not exist or is revoked
    enum DelegationType {
        NONE,
        ALL,
        CONTRACT,
        ERC721,
        ERC20,
        ERC1155
    }

    /// @notice Struct for returning delegations
    struct Delegation {
        DelegationType type_;
        address to;
        address from;
        bytes32 rights;
        address contract_;
        uint256 tokenId;
        uint256 amount;
    }

    /// @notice Emitted when an address delegates or revokes rights for their entire wallet
    event DelegateAll(address indexed from, address indexed to, bytes32 rights, bool enable);

    /// @notice Emitted when an address delegates or revokes rights for a contract address
    event DelegateContract(address indexed from, address indexed to, address indexed contract_, bytes32 rights, bool enable);

    /// @notice Emitted when an address delegates or revokes rights for an ERC721 tokenId
    event DelegateERC721(address indexed from, address indexed to, address indexed contract_, uint256 tokenId, bytes32 rights, bool enable);

    /// @notice Emitted when an address delegates or revokes rights for an amount of ERC20 tokens
    event DelegateERC20(address indexed from, address indexed to, address indexed contract_, bytes32 rights, uint256 amount);

    /// @notice Emitted when an address delegates or revokes rights for an amount of an ERC1155 tokenId
    event DelegateERC1155(address indexed from, address indexed to, address indexed contract_, uint256 tokenId, bytes32 rights, uint256 amount);

    /// @notice Thrown if multicall calldata is malformed
    error MulticallFailed();

    /**
     * -----------  WRITE -----------
     */

    /**
     * @notice Call multiple functions in the current contract and return the data from all of them if they all succeed
     * @param data The encoded function data for each of the calls to make to this contract
     * @return results The results from each of the calls passed in via data
     */
    function multicall(bytes[] calldata data) external payable returns (bytes[] memory results);

    /**
     * @notice Allow the delegate to act on behalf of `msg.sender` for all contracts
     * @param to The address to act as delegate
     * @param rights Specific subdelegation rights granted to the delegate, pass an empty bytestring to encompass all rights
     * @param enable Whether to enable or disable this delegation, true delegates and false revokes
     * @return delegationHash The unique identifier of the delegation
     */
    function delegateAll(address to, bytes32 rights, bool enable) external payable returns (bytes32 delegationHash);

    /**
     * @notice Allow the delegate to act on behalf of `msg.sender` for a specific contract
     * @param to The address to act as delegate
     * @param contract_ The contract whose rights are being delegated
     * @param rights Specific subdelegation rights granted to the delegate, pass an empty bytestring to encompass all rights
     * @param enable Whether to enable or disable this delegation, true delegates and false revokes
     * @return delegationHash The unique identifier of the delegation
     */
    function delegateContract(address to, address contract_, bytes32 rights, bool enable) external payable returns (bytes32 delegationHash);

    /**
     * @notice Allow the delegate to act on behalf of `msg.sender` for a specific ERC721 token
     * @param to The address to act as delegate
     * @param contract_ The contract whose rights are being delegated
     * @param tokenId The token id to delegate
     * @param rights Specific subdelegation rights granted to the delegate, pass an empty bytestring to encompass all rights
     * @param enable Whether to enable or disable this delegation, true delegates and false revokes
     * @return delegationHash The unique identifier of the delegation
     */
    function delegateERC721(address to, address contract_, uint256 tokenId, bytes32 rights, bool enable) external payable returns (bytes32 delegationHash);

    /**
     * @notice Allow the delegate to act on behalf of `msg.sender` for a specific amount of ERC20 tokens
     * @dev The actual amount is not encoded in the hash, just the existence of a amount (since it is an upper bound)
     * @param to The address to act as delegate
     * @param contract_ The address for the fungible token contract
     * @param rights Specific subdelegation rights granted to the delegate, pass an empty bytestring to encompass all rights
     * @param amount The amount to delegate, > 0 delegates and 0 revokes
     * @return delegationHash The unique identifier of the delegation
     */
    function delegateERC20(address to, address contract_, bytes32 rights, uint256 amount) external payable returns (bytes32 delegationHash);

    /**
     * @notice Allow the delegate to act on behalf of `msg.sender` for a specific amount of ERC1155 tokens
     * @dev The actual amount is not encoded in the hash, just the existence of a amount (since it is an upper bound)
     * @param to The address to act as delegate
     * @param contract_ The address of the contract that holds the token
     * @param tokenId The token id to delegate
     * @param rights Specific subdelegation rights granted to the delegate, pass an empty bytestring to encompass all rights
     * @param amount The amount of that token id to delegate, > 0 delegates and 0 revokes
     * @return delegationHash The unique identifier of the delegation
     */
    function delegateERC1155(address to, address contract_, uint256 tokenId, bytes32 rights, uint256 amount) external payable returns (bytes32 delegationHash);

    /**
     * ----------- CHECKS -----------
     */

    /**
     * @notice Check if `to` is a delegate of `from` for the entire wallet
     * @param to The potential delegate address
     * @param from The potential address who delegated rights
     * @param rights Specific rights to check for, pass the zero value to ignore subdelegations and check full delegations only
     * @return valid Whether delegate is granted to act on the from's behalf
     */
    function checkDelegateForAll(address to, address from, bytes32 rights) external view returns (bool);

    /**
     * @notice Check if `to` is a delegate of `from` for the specified `contract_` or the entire wallet
     * @param to The delegated address to check
     * @param contract_ The specific contract address being checked
     * @param from The cold wallet who issued the delegation
     * @param rights Specific rights to check for, pass the zero value to ignore subdelegations and check full delegations only
     * @return valid Whether delegate is granted to act on from's behalf for entire wallet or that specific contract
     */
    function checkDelegateForContract(address to, address from, address contract_, bytes32 rights) external view returns (bool);

    /**
     * @notice Check if `to` is a delegate of `from` for the specific `contract` and `tokenId`, the entire `contract_`, or the entire wallet
     * @param to The delegated address to check
     * @param contract_ The specific contract address being checked
     * @param tokenId The token id for the token to delegating
     * @param from The wallet that issued the delegation
     * @param rights Specific rights to check for, pass the zero value to ignore subdelegations and check full delegations only
     * @return valid Whether delegate is granted to act on from's behalf for entire wallet, that contract, or that specific tokenId
     */
    function checkDelegateForERC721(address to, address from, address contract_, uint256 tokenId, bytes32 rights) external view returns (bool);

    /**
     * @notice Returns the amount of ERC20 tokens the delegate is granted rights to act on the behalf of
     * @param to The delegated address to check
     * @param contract_ The address of the token contract
     * @param from The cold wallet who issued the delegation
     * @param rights Specific rights to check for, pass the zero value to ignore subdelegations and check full delegations only
     * @return balance The delegated balance, which will be 0 if the delegation does not exist
     */
    function checkDelegateForERC20(address to, address from, address contract_, bytes32 rights) external view returns (uint256);

    /**
     * @notice Returns the amount of a ERC1155 tokens the delegate is granted rights to act on the behalf of
     * @param to The delegated address to check
     * @param contract_ The address of the token contract
     * @param tokenId The token id to check the delegated amount of
     * @param from The cold wallet who issued the delegation
     * @param rights Specific rights to check for, pass the zero value to ignore subdelegations and check full delegations only
     * @return balance The delegated balance, which will be 0 if the delegation does not exist
     */
    function checkDelegateForERC1155(address to, address from, address contract_, uint256 tokenId, bytes32 rights) external view returns (uint256);

    /**
     * ----------- ENUMERATIONS -----------
     */

    /**
     * @notice Returns all enabled delegations a given delegate has received
     * @param to The address to retrieve delegations for
     * @return delegations Array of Delegation structs
     */
    function getIncomingDelegations(address to) external view returns (Delegation[] memory delegations);

    /**
     * @notice Returns all enabled delegations an address has given out
     * @param from The address to retrieve delegations for
     * @return delegations Array of Delegation structs
     */
    function getOutgoingDelegations(address from) external view returns (Delegation[] memory delegations);

    /**
     * @notice Returns all hashes associated with enabled delegations an address has received
     * @param to The address to retrieve incoming delegation hashes for
     * @return delegationHashes Array of delegation hashes
     */
    function getIncomingDelegationHashes(address to) external view returns (bytes32[] memory delegationHashes);

    /**
     * @notice Returns all hashes associated with enabled delegations an address has given out
     * @param from The address to retrieve outgoing delegation hashes for
     * @return delegationHashes Array of delegation hashes
     */
    function getOutgoingDelegationHashes(address from) external view returns (bytes32[] memory delegationHashes);

    /**
     * @notice Returns the delegations for a given array of delegation hashes
     * @param delegationHashes is an array of hashes that correspond to delegations
     * @return delegations Array of Delegation structs, return empty structs for nonexistent or revoked delegations
     */
    function getDelegationsFromHashes(bytes32[] calldata delegationHashes) external view returns (Delegation[] memory delegations);

    /**
     * ----------- STORAGE ACCESS -----------
     */

    /**
     * @notice Allows external contracts to read arbitrary storage slots
     */
    function readSlot(bytes32 location) external view returns (bytes32);

    /**
     * @notice Allows external contracts to read an arbitrary array of storage slots
     */
    function readSlots(bytes32[] calldata locations) external view returns (bytes32[] memory);
}
// File: @openzeppelin/contracts/security/ReentrancyGuard.sol


// OpenZeppelin Contracts v4.4.1 (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// File: @openzeppelin/contracts/utils/Strings.sol


// OpenZeppelin Contracts (last updated v4.7.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

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

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}

// File: @openzeppelin/contracts/utils/Context.sol


// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity ^0.8.0;


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
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
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

// File: @openzeppelin/contracts/utils/Address.sol


// OpenZeppelin Contracts (last updated v4.7.0) (utils/Address.sol)

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
                /// @solidity memory-safe-assembly
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

// File: @openzeppelin/contracts/token/ERC721/IERC721Receiver.sol


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC721/IERC721Receiver.sol)

pragma solidity ^0.8.0;

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

// File: @openzeppelin/contracts/interfaces/IERC2981.sol


// OpenZeppelin Contracts (last updated v4.6.0) (interfaces/IERC2981.sol)

pragma solidity ^0.8.0;


/**
 * @dev Interface for the NFT Royalty Standard.
 *
 * A standardized way to retrieve royalty payment information for non-fungible tokens (NFTs) to enable universal
 * support for royalty payments across all NFT marketplaces and ecosystem participants.
 *
 * _Available since v4.5._
 */
interface IERC2981 is IERC165 {
    /**
     * @dev Returns how much royalty is owed and to whom, based on a sale price that may be denominated in any unit of
     * exchange. The royalty amount is denominated and should be paid in that same unit of exchange.
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        returns (address receiver, uint256 royaltyAmount);
}

// File: @openzeppelin/contracts/utils/introspection/ERC165.sol


// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

pragma solidity ^0.8.0;


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

// File: @openzeppelin/contracts/token/ERC721/IERC721.sol


// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC721/IERC721.sol)

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

// File: @openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol


// OpenZeppelin Contracts v4.4.1 (token/ERC721/extensions/IERC721Metadata.sol)

pragma solidity ^0.8.0;


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

// File: tinyERC721_ID.sol


pragma solidity ^0.8.24;








error ApprovalCallerNotOwnerNorApproved();
error ApprovalQueryForNonexistentToken();
error ApproveToCaller();
error ApprovalToCurrentOwner();
error BalanceQueryForZeroAddress();
error MintToZeroAddress();
error MintZeroQuantity();
error TokenDataQueryForNonexistentToken();
error OwnerQueryForNonexistentToken();
error OperatorQueryForNonexistentToken();
error TransferCallerNotOwnerNorApproved();
error TransferFromIncorrectOwner();
error TransferToNonERC721ReceiverImplementer();
error TransferToZeroAddress();
error URIQueryForNonexistentToken();

contract TinyERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    struct TokenData {
        address owner;
        bytes12 aux;
    }

    uint256 private immutable _maxBatchSize;

    mapping(uint256 => TokenData) private _tokens;
    uint256 private _mintCounter = 50;
    mapping(uint256 => bool) private _claimedTokens;

    string private _name;
    string private _symbol;

    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxBatchSize_
    ) {
        _name = name_;
        _symbol = symbol_;
        _maxBatchSize = maxBatchSize_;
    }

    function totalSupply() public view virtual returns (uint256) {
        uint256 claimedCount = 0;
        for (uint256 i = 0; i < 50; i++) {
            if (_claimedTokens[i]) {
                claimedCount += 1;
            }
        }
        // _mintCounter starts at 50, so subtract 50 to get the number of tokens minted above ID 49
        return claimedCount + (_mintCounter - 50);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override returns (string memory) {
        if (!_exists(tokenId)) revert URIQueryForNonexistentToken();

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString()))
                : "";
    }

    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    function balanceOf(
        address owner
    ) public view virtual override returns (uint256) {
        if (owner == address(0)) revert BalanceQueryForZeroAddress();

        uint256 count = 0;
        // Check claimed tokens in the 0-49 range
        for (uint256 i = 0; i < 50; i++) {
            if (_claimedTokens[i] && _tokens[i].owner == owner) {
                count += 1;
            }
        }
        // Check minted tokens above ID 49
        for (uint256 i = 50; i < _mintCounter; i++) {
            if (_tokens[i].owner == owner) {
                count += 1;
            }
        }
        return count;
    }

    function _tokenData(
        uint256 tokenId
    ) internal view returns (TokenData storage) {
        if (!_exists(tokenId)) revert TokenDataQueryForNonexistentToken();

        TokenData storage token = _tokens[tokenId];
        uint256 currentIndex = tokenId;
        while (token.owner == address(0)) {
            unchecked {
                --currentIndex;
            }
            token = _tokens[currentIndex];
        }

        return token;
    }

    function ownerOf(
        uint256 tokenId
    ) public view virtual override returns (address) {
        if (!_exists(tokenId)) revert OwnerQueryForNonexistentToken();
        return _tokenData(tokenId).owner;
    }

    function approve(address to, uint256 tokenId) public virtual override {
        TokenData memory token = _tokenData(tokenId);
        address owner = token.owner;
        if (to == owner) revert ApprovalToCurrentOwner();

        if (_msgSender() != owner && !isApprovedForAll(owner, _msgSender())) {
            revert ApprovalCallerNotOwnerNorApproved();
        }

        _approve(to, tokenId, token);
    }

    function getApproved(
        uint256 tokenId
    ) public view virtual override returns (address) {
        if (!_exists(tokenId)) revert ApprovalQueryForNonexistentToken();

        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override {
        if (operator == _msgSender()) revert ApproveToCaller();

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(
        address owner,
        address operator
    ) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        TokenData memory token = _tokenData(tokenId);
        if (!_isApprovedOrOwner(_msgSender(), tokenId, token))
            revert TransferCallerNotOwnerNorApproved();

        _transfer(from, to, tokenId, token);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        TokenData memory token = _tokenData(tokenId);
        if (!_isApprovedOrOwner(_msgSender(), tokenId, token))
            revert TransferCallerNotOwnerNorApproved();

        _safeTransfer(from, to, tokenId, token, _data);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        TokenData memory token,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId, token);

        if (
            to.isContract() && !_checkOnERC721Received(from, to, tokenId, _data)
        ) revert TransferToNonERC721ReceiverImplementer();
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        if (tokenId < 50) {
            return _claimedTokens[tokenId];
        } else {
            return tokenId < _mintCounter;
        }
    }

    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId,
        TokenData memory token
    ) internal view virtual returns (bool) {
        address owner = token.owner;
        return (spender == owner ||
            isApprovedForAll(owner, spender) ||
            getApproved(tokenId) == spender);
    }

    function _safeMint(address to, uint256 quantity) internal virtual {
        _safeMint(to, quantity, "");
    }

    function _safeMintID(address to, uint256 _id) internal virtual {
        _safeMintID(to, _id, "");
    }

    function _safeMint(
        address to,
        uint256 quantity,
        bytes memory _data
    ) internal virtual {
        uint256 startTokenId = _mintCounter;
        _mint(to, quantity);

        if (to.isContract()) {
            unchecked {
                for (uint256 i; i < quantity; ++i) {
                    if (
                        !_checkOnERC721Received(
                            address(0),
                            to,
                            startTokenId + i,
                            _data
                        )
                    ) revert TransferToNonERC721ReceiverImplementer();
                }
            }
        }
    }

    function _safeMintID(
        address to,
        uint256 _id,
        bytes memory _data
    ) internal virtual {
        require(_id < 50, "ID must be less than 50 for this function");
        require(!_claimedTokens[_id], "Token ID already claimed");

        _claimedTokens[_id] = true;
        _tokens[_id].owner = to;
        _mintID(to, _id, 1);
        if (to.isContract()) {
            if (!_checkOnERC721Received(address(0), to, _id, _data))
                revert TransferToNonERC721ReceiverImplementer();
        }
    }

    function _mint(address to, uint256 quantity) internal virtual {
        if (to == address(0)) revert MintToZeroAddress();
        if (quantity == 0) revert MintZeroQuantity();

        uint256 startTokenId = _mintCounter;
        _beforeTokenTransfers(address(0), to, startTokenId, quantity);

        unchecked {
            for (uint256 i; i < quantity; ++i) {
                if (_maxBatchSize == 0 ? i == 0 : i % _maxBatchSize == 0) {
                    TokenData storage token = _tokens[startTokenId + i];
                    token.owner = to;
                    token.aux = _calculateAux(
                        address(0),
                        to,
                        startTokenId + i,
                        0
                    );
                }

                emit Transfer(address(0), to, startTokenId + i);
            }
            _mintCounter += quantity;
        }

        _afterTokenTransfers(address(0), to, startTokenId, quantity);
    }

    function _mintID(
        address to,
        uint256 _id,
        uint256 quantity
    ) internal virtual {
        if (to == address(0)) revert MintToZeroAddress();
        if (quantity == 0) revert MintZeroQuantity();

        uint256 startTokenId = _id;
        _beforeTokenTransfers(address(0), to, startTokenId, quantity);

        unchecked {
            for (uint256 i; i < quantity; ++i) {
                if (_maxBatchSize == 0 ? i == 0 : i % _maxBatchSize == 0) {
                    TokenData storage token = _tokens[startTokenId + i];
                    token.owner = to;
                    token.aux = _calculateAux(
                        address(0),
                        to,
                        startTokenId + i,
                        0
                    );
                }

                emit Transfer(address(0), to, startTokenId + i);
            }
        }

        _afterTokenTransfers(address(0), to, startTokenId, quantity);
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId,
        TokenData memory token
    ) internal virtual {
        if (token.owner != from) revert TransferFromIncorrectOwner();
        if (to == address(0)) revert TransferToZeroAddress();

        _beforeTokenTransfers(from, to, tokenId, 1);

        _approve(address(0), tokenId, token);

        unchecked {
            uint256 nextTokenId = tokenId + 1;
            if (_exists(nextTokenId)) {
                TokenData storage nextToken = _tokens[nextTokenId];
                if (nextToken.owner == address(0)) {
                    nextToken.owner = token.owner;
                    nextToken.aux = token.aux;
                }
            }
        }

        TokenData storage newToken = _tokens[tokenId];
        newToken.owner = to;
        newToken.aux = _calculateAux(from, to, tokenId, token.aux);

        emit Transfer(from, to, tokenId);

        _afterTokenTransfers(from, to, tokenId, 1);
    }

    function _calculateAux(
        address from,
        address to,
        uint256 tokenId,
        bytes12 current
    ) internal view virtual returns (bytes12) {}

    function _approve(
        address to,
        uint256 tokenId,
        TokenData memory token
    ) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(token.owner, to, tokenId);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        try
            IERC721Receiver(to).onERC721Received(
                _msgSender(),
                from,
                tokenId,
                _data
            )
        returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch (bytes memory reason) {
            if (reason.length == 0) {
                revert TransferToNonERC721ReceiverImplementer();
            } else {
                assembly {
                    revert(add(32, reason), mload(reason))
                }
            }
        }
    }

    function _beforeTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual {}

    function _afterTokenTransfers(
        address from,
        address to,
        uint256 startTokenId,
        uint256 quantity
    ) internal virtual {}
}

// File: curatedTemplate.sol

/*
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMNOOXMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMXO0NMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMk,'lKWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMKc.,kWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMNo...cKMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMKc...lNMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMK:....cKMMMMMMMMMMMMMMMMMMMMMMMMMMMMMKc....:0MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMk,.....cKMMMMMMMMMMMMMMMMMMMMMMMMMMWKc.....,kWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMNd.......cKWMMMMMMMMMMMMMMMMMMMMMMMKkc.......oNMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMKc........cKMMMMMMMMMMMMMMMMMMMMMMKc'........cKMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMO,.........cKMMMMMMMMMMMMMMMMMMMMKc..........,OMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMWd'..........cKWMMMMMMMMMMMMMMMMMKl............dWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMXc...;;.......cKMMMMMMMMMMMMMMMMKc...'co,......cXMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMO;..,x0:.......cKMMMMMMMMMMMMMMKl...cxKKc......;OMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMWd'..;0W0:.......cKWMMMMMMMMMMMKc...cKWMNo......'xWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMXl...lXMW0:.......c0WMMMMMMMMMKl...cKMMMWx'......lXXkxxddddoddddxxxkO0KXXNWWWMMMMMMMMMMM
MMMMMMMMMMMM0;...dWMMW0:.......c0WMMMMMMMKl...cKMMMMMO;......;0k,.'''',,''.......'',;::cxXMMMMMMMMMM
MMMMMMMMMMMWx'..,kMMMMW0:.......c0WMMMMMKl...cKMMMMWWKc......'xXOO00KKKKK00Okdoc,'......cKMMMMMMMMMM
MMMMMMMMMMMXl...:0MMMMMW0:.......:0WMMMKl...cKMMWKkdxKd.......oNMMMMMMMMMMMMMMMWXOd:'...lXMMMMMMMMMM
MMMMMMMMMMM0:...lXMMMMMMWO:.......:0MMKl...cKMWKo,..;0k,......:KMMMMMMMMMMMMMMMMMMWNOc'.oNMMMMMMMMMM
MMMMMMMMMMWx'..'dWMMMMMMMW0:.......:0Kl...cKMNk;....,k0:......,kMMMMMMMMMMMMMMMMMMMMMXl'oNMMMMMMMMMM
MMMMMMMMMMNl...,OMMMMMMMMMW0:.......;;...cKWXo'......dKl.......oNMMMMMMMMMMMMMMMMMMMMM0:dWMMMMMMMMMM
MMMMMMMMMM0:...:KMMMMMMMMMMW0c..........lKMNo'.......oXd'......cKMMMMMMMMMMMMMMMMMMMMMNKXMMMMMMMMMMM
MMMMMMMMMWk,...lXMMMMMMMMMMMWKc........cKMWx,.......,kWk,......,OMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMNo...'dWMMMMMMMMMMMMMKl......lKMMK:........:KMK:.......dNMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMWO;...'xWMMMMMMMMMMMMMMXl'...lKMMWx'........lXMXl.......;OWMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMNKOOd;.....;dkO0NMMMMMMMMMMMXo''lXMMMNo.........lNW0:........,lxkO0XWMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMN0kkkkkkkkkkxxkOXWMMMMMMMMMMMN0ONMMMMNo.........lXWXOkkkkxxxxxxxxxk0WMXOkkkkkkkkkkkkkkkkkOXMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNo.........:0MMMMMMMMMMMMMMMMMMMMN0OOxl,........,lxO0NMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWx'........'xWMMMMMMMMMMMMMMMMMMMMMMMMNd'......'dNMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM0:.........:KMMMMMMMMMMMMMMMMMMMMMMMMMk,......'xWMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNd'.........oXMMMMMMMMMMMMMMMMMMMMMMMMO,......'kWMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMXo.........'oXMMMMMMMMMMMMMMMMMMMMMMMO,......'kMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMXo'.........c0WMMMMMMMMMMMMMMMMMMMMMO,......'kMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMNx;.........,dXWMMMMMMMMMMMMMMMMMMMO,......'kMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWKo;'........;d0NMMMMMMMMMMMMMMMMMO,......'kWMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWKOxc'.......':dOKNWMMMMMMMMMMMWk,......'kWMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMN0xl;'.......,:ldxkO00KK00Od:.......;OMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWX0kdl:;''.......''''''....',;cox0NMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMWNXK0OkxxddddddddxxkkO0XNWMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
MMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM
*/

// Contract authored by August Rosedale (@augustfr)
// https://miragegallery.ai

pragma solidity ^0.8.24;






interface mirageContracts {
    function balanceOf(
        address owner,
        uint256 _id
    ) external view returns (uint256);
}

contract mirageCuratedTemplate is
    TinyERC721,
    ReentrancyGuard,
    Ownable,
    IERC2981
{
    using Strings for uint256;

    mapping(uint256 => uint256) public sentientClaimed;

    IDelegateRegistry public immutable registry;

    uint256 private miragePercentage = 15;
    address private mirageAddress = 0x4a462cbf4902A8D26bF2c6931F12260d8fcEC69e;

    uint256 private royaltyAmount = 1000;
    address private royaltyAddress = 0xdCB23900d19b808F5510E8bB84E9B6988a797bb2;

    bool public metadataFrozen;

    bool public presaleOpen = false;
    bool public publicSaleOpen = false;
    bool public sentientClaimOpen = false;

    uint256 public maxPerPublicTx = 10;

    address public admin;

    modifier onlyAdmin() {
        require(
            msg.sender == admin || msg.sender == owner(),
            "Only admin or owner"
        );
        _;
    }

    struct ProjectDetails {
        uint256 artworks;
        string artistName;
        string projectDescription;
        string projectName;
        address artistAddress;
        string baseURI;
        string projectWebsite;
        string projectLicense;
        uint256 maxSupply;
        uint256 maxPresale;
        uint256 mintPrice;
        address additionalPayeeAddress;
        uint256 additionalPayeePercentage;
    }

    ProjectDetails public projectDetails;

    mirageContracts public membershipContract;
    address private membershipAddress;

    constructor(
        string memory name,
        string memory symbol,
        address _registry,
        address _membershipAddress
    ) TinyERC721(name, symbol, 0) {
        membershipContract = mirageContracts(_membershipAddress);
        membershipAddress = _membershipAddress;
        admin = msg.sender;
        registry = IDelegateRegistry(_registry);
    }

    function addProjectDetails(
        uint256 _mintPrice,
        string memory _artistName,
        string memory _projectDescription,
        string memory _projectName,
        address _artistAddress,
        string memory _baseURI,
        string memory _projectWebsite,
        string memory _projectLicense,
        uint256 _maxSupply,
        uint256 _maxPresale
    ) public onlyAdmin {
        projectDetails.artworks = 50;
        projectDetails.mintPrice = _mintPrice;
        projectDetails.artistName = _artistName;
        projectDetails.projectDescription = _projectDescription;
        projectDetails.projectName = _projectName;
        projectDetails.artistAddress = _artistAddress;
        projectDetails.baseURI = _baseURI;
        projectDetails.projectWebsite = _projectWebsite;
        projectDetails.projectLicense = _projectLicense;
        projectDetails.maxSupply = _maxSupply;
        projectDetails.maxPresale = _maxPresale;
    }

    function updateAdminAddress(address _newAdmin) public onlyAdmin {
        admin = _newAdmin;
    }

    function setAdditionalPayee(
        address _additionalPayee,
        uint256 _additionalPayeePercentage
    ) external onlyAdmin {
        require(_additionalPayee != address(0), "Invalid address");
        require(
            _additionalPayeePercentage <= 100,
            "Percentage cannot exceed 100"
        );
        projectDetails.additionalPayeeAddress = _additionalPayee;
        projectDetails.additionalPayeePercentage = _additionalPayeePercentage;
    }

    function projectTokenInfo()
        public
        view
        returns (
            address artistAddress,
            uint256 pricePerTokenInWei,
            uint256 artworks,
            uint256 maxArtworks,
            uint256 maxEarly,
            address additionalPayee,
            uint256 additionalPayeePercentage,
            bool publicActive,
            bool earlyActive,
            string memory currency
        )
    {
        artistAddress = projectDetails.artistAddress;
        pricePerTokenInWei = projectDetails.mintPrice;
        artworks = projectDetails.artworks + 50;
        maxArtworks = projectDetails.maxSupply;
        maxEarly = projectDetails.maxPresale;
        additionalPayee = projectDetails.additionalPayeeAddress;
        additionalPayeePercentage = projectDetails.additionalPayeePercentage;
        publicActive = publicSaleOpen;
        earlyActive = presaleOpen;
        currency = "ETH";
    }

    function updateMirageAddress(address _newMirageAddress) public onlyAdmin {
        require(_newMirageAddress != address(0), "Invalid address");
        mirageAddress = _newMirageAddress;
    }

    function updateMaxPerPublicTx(uint256 _newAmount) public onlyAdmin {
        maxPerPublicTx = _newAmount;
    }

    function updateProjectDetails(
        uint256 _mintPrice,
        string memory _artistName,
        string memory _projectDescription,
        string memory _projectName,
        address _artistAddress,
        string memory _baseURI,
        string memory _projectWebsite,
        string memory _projectLicense,
        uint256 _maxSupply,
        uint256 _maxPresale,
        address _additionalPayeeAddress,
        uint256 _additionalPayeePercentage
    ) public onlyAdmin {
        require(!metadataFrozen, "Metadata is frozen");
        projectDetails.mintPrice = _mintPrice;
        projectDetails.artistName = _artistName;
        projectDetails.projectDescription = _projectDescription;
        projectDetails.projectName = _projectName;
        projectDetails.artistAddress = _artistAddress;
        projectDetails.baseURI = _baseURI;
        projectDetails.projectWebsite = _projectWebsite;
        projectDetails.projectLicense = _projectLicense;
        projectDetails.maxSupply = _maxSupply;
        projectDetails.maxPresale = _maxPresale;
        projectDetails.additionalPayeeAddress = _additionalPayeeAddress;
        projectDetails.additionalPayeePercentage = _additionalPayeePercentage;
    }

    function togglePresale() public onlyAdmin {
        presaleOpen = !presaleOpen;
        sentientClaimOpen = true;
    }

    function togglePublicSale() public onlyAdmin {
        publicSaleOpen = !publicSaleOpen;
        sentientClaimOpen = true;
        presaleOpen = false;
    }

    function earlyMemberPurchase(
        uint256 _membershipId,
        address _vault
    ) public payable nonReentrant {
        require(
            msg.value >= projectDetails.mintPrice,
            "Ether sent is insufficient"
        );
        require(
            projectDetails.artworks - 50 < projectDetails.maxPresale,
            "Max supply exceeded"
        );
        require(presaleOpen, "Presale is not open");

        address requester = _vault == msg.sender ? msg.sender : _vault;
        bool isValidDelegate = _vault == msg.sender
            ? true
            : registry.checkDelegateForContract(
                msg.sender,
                _vault,
                membershipAddress,
                ""
            );
        require(isValidDelegate, "Invalid delegate-vault pairing");
        require(
            membershipContract.balanceOf(requester, _membershipId) > 0,
            "Membership token missing"
        );

        _splitFunds(1);
        projectDetails.artworks += 1;
        _safeMint(requester, 1);
    }

    function purchase(uint256 numberOfTokens) public payable nonReentrant {
        require(publicSaleOpen, "Public sale is not open");
        require(
            numberOfTokens <= maxPerPublicTx,
            "Exceeds max tokens per transaction"
        );
        require(
            msg.value >= projectDetails.mintPrice * numberOfTokens,
            "Insufficient payment"
        );
        require(
            msg.sender == tx.origin,
            "Calls must be made directly by a user"
        );
        require(
            projectDetails.artworks + numberOfTokens <=
                projectDetails.maxSupply,
            "Would exceed max supply"
        );

        _splitFunds(numberOfTokens);
        projectDetails.artworks += numberOfTokens;
        _safeMint(msg.sender, numberOfTokens);
    }

    function claimSentient(uint256 membershipId, address _vault) public {
        require(membershipId < 50, "Invalid Sentient ID");
        require(sentientClaimOpen, "Sentient claim is not open");

        address requester = _vault == msg.sender ? msg.sender : _vault;
        bool isValidDelegate = _vault == msg.sender
            ? true
            : registry.checkDelegateForContract(
                msg.sender,
                _vault,
                membershipAddress,
                ""
            );
        require(isValidDelegate, "Invalid delegate-vault pairing");
        require(
            membershipContract.balanceOf(requester, membershipId) > 0,
            "Membership token missing"
        );

        _safeMintID(requester, membershipId);
    }

    function freezeMetadata() public onlyAdmin {
        require(!metadataFrozen, "Already frozen");
        metadataFrozen = true;
    }

    function tokenURI(
        uint256 tokenID
    ) public view override returns (string memory) {
        if (!_exists(tokenID)) revert URIQueryForNonexistentToken();
        return string.concat(projectDetails.baseURI, Strings.toString(tokenID));
    }

    function updateURI(string memory _baseTokenURI) external onlyAdmin {
        require(!metadataFrozen, "Metadata is frozen");
        projectDetails.baseURI = _baseTokenURI;
    }

    function withdraw() public onlyAdmin {
        payable(msg.sender).transfer(address(this).balance);
    }

    function _splitFunds(uint256 numberOfTokens) internal {
        if (msg.value == 0) return;

        uint256 mintCost = projectDetails.mintPrice * numberOfTokens;
        uint256 refund = msg.value - mintCost;
        if (refund > 0) {
            payable(msg.sender).transfer(refund);
        }

        uint256 mirageAmount = (mintCost * miragePercentage) / 100;
        if (mirageAmount > 0) {
            payable(mirageAddress).transfer(mirageAmount);
        }

        uint256 remainingFunds = mintCost - mirageAmount;
        uint256 additionalPayeeAmount = 0;
        if (projectDetails.additionalPayeePercentage > 0) {
            additionalPayeeAmount =
                (remainingFunds * projectDetails.additionalPayeePercentage) /
                100;
            if (additionalPayeeAmount > 0) {
                payable(projectDetails.additionalPayeeAddress).transfer(
                    additionalPayeeAmount
                );
            }
        }

        uint256 creatorFunds = remainingFunds - additionalPayeeAmount;
        if (creatorFunds > 0) {
            payable(projectDetails.artistAddress).transfer(creatorFunds);
        }
    }

    function royaltyInfo(
        uint256 /* tokenId */,
        uint256 salePrice
    ) external view override returns (address receiver, uint256 royaltyFee) {
        uint256 totalRoyalty = (salePrice * royaltyAmount) / 10000;

        return (royaltyAddress, totalRoyalty);
    }

    function updateRoyaltyInfo(
        address _royaltyAddress,
        uint256 _royaltyAmount
    ) external onlyAdmin {
        require(_royaltyAmount <= 10000, "Royalty cannot exceed 100%");
        royaltyAddress = _royaltyAddress;
        royaltyAmount = _royaltyAmount;
    }
}