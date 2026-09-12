// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

library AddressUpgradeable {
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
     * https://consensys.net/diligence/blog/2019/09/stop-using-soliditys-transfer-now/[Learn more].
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
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
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
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
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
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
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


interface IERC165Upgradeable {
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


abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     * @custom:oz-retyped-from bool
     */
    uint8 private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Triggered when the contract has been initialized or reinitialized.
     */
    event Initialized(uint8 version);

    /**
     * @dev A modifier that defines a protected initializer function that can be invoked at most once. In its scope,
     * `onlyInitializing` functions can be used to initialize parent contracts.
     *
     * Similar to `reinitializer(1)`, except that functions marked with `initializer` can be nested in the context of a
     * constructor.
     *
     * Emits an {Initialized} event.
     */
    modifier initializer() {
        bool isTopLevelCall = !_initializing;
        require(
            (isTopLevelCall && _initialized < 1) || (!AddressUpgradeable.isContract(address(this)) && _initialized == 1),
            "Initializable: contract is already initialized"
        );
        _initialized = 1;
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(1);
        }
    }

    /**
     * @dev A modifier that defines a protected reinitializer function that can be invoked at most once, and only if the
     * contract hasn't been initialized to a greater version before. In its scope, `onlyInitializing` functions can be
     * used to initialize parent contracts.
     *
     * A reinitializer may be used after the original initialization step. This is essential to configure modules that
     * are added through upgrades and that require initialization.
     *
     * When `version` is 1, this modifier is similar to `initializer`, except that functions marked with `reinitializer`
     * cannot be nested. If one is invoked in the context of another, execution will revert.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     *
     * WARNING: setting the version to 255 will prevent any future reinitialization.
     *
     * Emits an {Initialized} event.
     */
    modifier reinitializer(uint8 version) {
        require(!_initializing && _initialized < version, "Initializable: contract is already initialized");
        _initialized = version;
        _initializing = true;
        _;
        _initializing = false;
        emit Initialized(version);
    }

    /**
     * @dev Modifier to protect an initialization function so that it can only be invoked by functions with the
     * {initializer} and {reinitializer} modifiers, directly or indirectly.
     */
    modifier onlyInitializing() {
        require(_initializing, "Initializable: contract is not initializing");
        _;
    }

    /**
     * @dev Locks the contract, preventing any future reinitialization. This cannot be part of an initializer call.
     * Calling this in the constructor of a contract will prevent that contract from being initialized or reinitialized
     * to any version. It is recommended to use this to lock implementation contracts that are designed to be called
     * through proxies.
     *
     * Emits an {Initialized} event the first time it is successfully executed.
     */
    function _disableInitializers() internal virtual {
        require(!_initializing, "Initializable: contract is initializing");
        if (_initialized != type(uint8).max) {
            _initialized = type(uint8).max;
            emit Initialized(type(uint8).max);
        }
    }

    /**
     * @dev Internal function that returns the initialized version. Returns `_initialized`
     */
    function _getInitializedVersion() internal view returns (uint8) {
        return _initialized;
    }

    /**
     * @dev Internal function that returns the initialized version. Returns `_initializing`
     */
    function _isInitializing() internal view returns (bool) {
        return _initializing;
    }
}


interface IAccessControl {
    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {AccessControl-_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) external view returns (bool);

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {AccessControl-_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) external view returns (bytes32);

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) external;

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) external;
}


abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}


abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}


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
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
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
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
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
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    /**
     * @dev Tool to verify that a low level call to smart-contract was successful, and revert (either by bubbling
     * the revert reason or using the provided one) in case of unsuccessful call or if target was not a contract.
     *
     * _Available since v4.8._
     */
    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                // only check isContract if the call was successful and the return data is empty
                // otherwise we already know that it was a contract
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

    /**
     * @dev Tool to verify that a low level call was successful, and revert if it wasn't, either by bubbling the
     * revert reason or using the provided one.
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
            _revert(returndata, errorMessage);
        }
    }

    function _revert(bytes memory returndata, string memory errorMessage) private pure {
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


abstract contract ERC165Upgradeable is Initializable, IERC165Upgradeable {
    function __ERC165_init() internal onlyInitializing {
    }

    function __ERC165_init_unchained() internal onlyInitializing {
    }
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165Upgradeable).interfaceId;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


enum DataVersion {invalid, common}

library CommonDataFormat {
    struct CommonData {
        bytes4 selector;
        address contractAddress;
        address account;
        address requester;
    }

    function encodeToCommonFormat(CommonData memory data) internal pure returns (bytes memory encoded) {
        return abi.encode(data);
    }

    function decodeFromCommonFormat(bytes memory request) internal pure returns (CommonData memory data) {
        return abi.decode(request, (CommonData));
    }

    function manufactureToCommon(bytes memory request) internal pure returns (bytes memory commonData) {
        return request;
    }

    function dataVersion() internal pure returns (uint) {
        return uint(DataVersion.common);
    }
}

/** 
 * //===== EXAMPLE =====//
 *  struct CustomData {
 *      CommonDataFormat.CommonData common;
 *      uint cap;
 *  }
 *
 *   library CustomDataFormat {
 *       function encodeToCustomFormat(CustomData memory data) internal pure returns (bytes memory encoded) {
 *           return abi.encode(data);
 *       }
 *
 *       function decodeFromCustomFormat(bytes memory request) internal pure returns (CustomData memory data) {
 *           return abi.decode(request, (CustomData));
 *       }
 *
 *       function manufactureCustomToCommon(bytes memory request) internal pure returns (bytes memory customData) {
 *           return abi.encode(decodeFromCustomFormat(request).common);
 *       }
 * 
 *       function manufactureCommonToCustom(bytes memory request) internal pure returns (bytes memory customData) {
 *           CommonData memory common = CommonDataFormat.decodeFromCommonFormat(request);
 *           return abi.encode(CustomData(common, 0));
 *       }
 * 
 *       function dataVersion() internal pure returns (DataVersion) {
 *           return DataVersion.custom;
 *       }
 *   }
 *
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


interface IVerifyKey {
    function getVerifyKey(address user, bytes32 functionName) external view returns (bytes32);
}

library Counters {
    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}


interface IRoleManager is IAccessControl {
    //===== FUNCTIONS =====//
    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
    //===== VIEW FUNCTIONS =====//
    function getRoleList(bytes32 role) external view returns (address[] memory);
}

interface IERC721Lockable {
    event Locked(uint256 indexed tokenId);
    event Unlocked(uint256 indexed tokenId);

    /** @dev External function that checks the lock status of the token.
     *  @param tokenId to check
     *  @return is locked (true : locked, false : unlocked)
     */
    function isLocked(uint256 tokenId) external view returns (bool);
}


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
        require(owner != address(0), "ERC721: address zero is not a valid owner");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: invalid token ID");
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
        _requireMinted(tokenId);

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
            "ERC721: approve caller is not token owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        _requireMinted(tokenId);

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
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");

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
        bytes memory data
    ) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");
        _safeTransfer(from, to, tokenId, data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `data` is additional data, it has no specified format and it is sent in call to `to`.
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
        bytes memory data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "ERC721: transfer to non ERC721Receiver implementer");
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
        bytes memory data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, data),
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
        delete _tokenApprovals[tokenId];

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
        delete _tokenApprovals[tokenId];

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);

        _afterTokenTransfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits an {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Approve `operator` to operate on all of `owner` tokens
     *
     * Emits an {ApprovalForAll} event.
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
     * @dev Reverts if the `tokenId` has not been minted yet.
     */
    function _requireMinted(uint256 tokenId) internal view virtual {
        require(_exists(tokenId), "ERC721: invalid token ID");
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) private returns (bool) {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    /// @solidity memory-safe-assembly
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


interface IRiskManager is IERC165Upgradeable {
    //===== VIEW FUNCTIONS =====//
    function isRiskedRequest(uint version, bytes memory request) external view returns (bool);
    function isRiskedRequests(uint version, bytes[] memory requests) external view returns (bool);
}

interface IArbSys {
    function arbBlockNumber() external view returns (uint);
}

library UnaLib {

    function blockNumber(uint chainId) internal view returns (uint) {
        return chainId == 421614 || chainId == 42161 ? IArbSys(0x0000000000000000000000000000000000000064).arbBlockNumber() : block.number;
    }
}

library Converter {
    /**
    * @dev Function to change bytes to bytes32
    */
    function bytesToBytes32(bytes memory input) internal pure returns (bytes32 output) {
        uint length = input.length >= 32 ? 32 : input.length;

        for (uint i = 0; i < length; i++) {
            output |= bytes32(input[i] & 0xFF) >> (i * 8);
        }
    }

    /**
    * @dev Function to change bytes32 to string
    */
    function bytes32ToString(bytes32 _bytes32) internal pure returns (string memory) {
        uint8 i = 0;
        while(i < 32 && _bytes32[i] != 0) {
            i++;
        }
        bytes memory bytesArray = new bytes(i);
        for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    /**
    * @dev Function to change string to bytes32
    * If string length is less than 32, pad for 0 (LSB)
    */
    function stringToBytes32(string memory source) internal pure returns (bytes32 result) {
        require(bytes(source).length <= 32, "E: string too long");
        assembly {
            result := mload(add(source, 32))
        }
    }

    function concat(string memory str1, string memory str2) internal pure returns (bytes32) {
        bytes memory concatenated = bytes(string(abi.encodePacked(str1, str2)));
        require(concatenated.length <= 32, "E: string too long");
        bytes32 result;

        assembly {
            result := mload(add(concatenated, 32))
        }
        return result;
    }
}

library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV
    }

    function _throwError(RecoverError error) private pure {
        if (error == RecoverError.NoError) {
            return; // no error: do nothing
        } else if (error == RecoverError.InvalidSignature) {
            revert("ECDSA: invalid signature");
        } else if (error == RecoverError.InvalidSignatureLength) {
            revert("ECDSA: invalid signature length");
        } else if (error == RecoverError.InvalidSignatureS) {
            revert("ECDSA: invalid signature 's' value");
        } else if (error == RecoverError.InvalidSignatureV) {
            revert("ECDSA: invalid signature 'v' value");
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature` or error string. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     *
     * Documentation for signature generation:
     * - with https://web3js.readthedocs.io/en/v1.3.4/web3-eth-accounts.html#sign[Web3.js]
     * - with https://docs.ethers.io/v5/api/signer/#Signer-signMessage[ethers]
     *
     * _Available since v4.3._
     */
    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError) {
        // Check the signature length
        // - case 65: r,s,v signature (standard)
        // - case 64: r,vs signature (cf https://eips.ethereum.org/EIPS/eip-2098) _Available since v4.1._
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            /// @solidity memory-safe-assembly
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        } else if (signature.length == 64) {
            bytes32 r;
            bytes32 vs;
            // ecrecover takes the signature parameters, and the only way to get them
            // currently is to use assembly.
            /// @solidity memory-safe-assembly
            assembly {
                r := mload(add(signature, 0x20))
                vs := mload(add(signature, 0x40))
            }
            return tryRecover(hash, r, vs);
        } else {
            return (address(0), RecoverError.InvalidSignatureLength);
        }
    }

    /**
     * @dev Returns the address that signed a hashed message (`hash`) with
     * `signature`. This address can then be used for verification purposes.
     *
     * The `ecrecover` EVM opcode allows for malleable (non-unique) signatures:
     * this function rejects them by requiring the `s` value to be in the lower
     * half order, and the `v` value to be either 27 or 28.
     *
     * IMPORTANT: `hash` _must_ be the result of a hash operation for the
     * verification to be secure: it is possible to craft signatures that
     * recover to arbitrary addresses for non-hashed data. A safe way to ensure
     * this is by receiving a hash of the original message (which may otherwise
     * be too long), and then calling {toEthSignedMessageHash} on it.
     */
    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, signature);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `r` and `vs` short-signature fields separately.
     *
     * See https://eips.ethereum.org/EIPS/eip-2098[EIP-2098 short signatures]
     *
     * _Available since v4.3._
     */
    function tryRecover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
     *
     * _Available since v4.2._
     */
    function recover(
        bytes32 hash,
        bytes32 r,
        bytes32 vs
    ) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, r, vs);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Overload of {ECDSA-tryRecover} that receives the `v`,
     * `r` and `s` signature fields separately.
     *
     * _Available since v4.3._
     */
    function tryRecover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address, RecoverError) {
        // EIP-2 still allows signature malleability for ecrecover(). Remove this possibility and make the signature
        // unique. Appendix F in the Ethereum Yellow paper (https://ethereum.github.io/yellowpaper/paper.pdf), defines
        // the valid range for s in (301): 0 < s < secp256k1n ÷ 2 + 1, and for v in (302): v ∈ {27, 28}. Most
        // signatures from current libraries generate a unique signature with an s-value in the lower half order.
        //
        // If your library generates malleable signatures, such as s-values in the upper range, calculate a new s-value
        // with 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141 - s1 and flip v from 27 to 28 or
        // vice versa. If your library also generates signatures with 0/1 for v instead 27/28, add 27 to v to accept
        // these malleable signatures as well.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return (address(0), RecoverError.InvalidSignatureS);
        }
        if (v != 27 && v != 28) {
            return (address(0), RecoverError.InvalidSignatureV);
        }

        // If the signature is valid (and not malleable), return the signer address
        address signer = ecrecover(hash, v, r, s);
        if (signer == address(0)) {
            return (address(0), RecoverError.InvalidSignature);
        }

        return (signer, RecoverError.NoError);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `v`,
     * `r` and `s` signature fields separately.
     */
    function recover(
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        (address recovered, RecoverError error) = tryRecover(hash, v, r, s);
        _throwError(error);
        return recovered;
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from a `hash`. This
     * produces hash corresponding to the one signed with the
     * https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`]
     * JSON-RPC method as part of EIP-191.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

    /**
     * @dev Returns an Ethereum Signed Message, created from `s`. This
     * produces hash corresponding to the one signed with the
     * https://eth.wiki/json-rpc/API#eth_sign[`eth_sign`]
     * JSON-RPC method as part of EIP-191.
     *
     * See {recover}.
     */
    function toEthSignedMessageHash(bytes memory s) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", Strings.toString(s.length), s));
    }

    /**
     * @dev Returns an Ethereum Signed Typed Data, created from a
     * `domainSeparator` and a `structHash`. This produces hash corresponding
     * to the one signed with the
     * https://eips.ethereum.org/EIPS/eip-712[`eth_signTypedData`]
     * JSON-RPC method as part of EIP-712.
     *
     * See {recover}.
     */
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}


abstract contract ERC721Lockable is IERC721Lockable, ERC721 {
    mapping(uint256 => bool) private _locked;

    /** @dev Lock the tokenId so that it cannot be transferred.
     *  @param tokenId to lock
     */
    function _lock(uint256 tokenId) internal virtual {
        require(_exists(tokenId), "ERC721Lockable: nonexistent token");
        require(!_locked[tokenId], "ERC721Lockable: invalid state");
        _locked[tokenId] = true;
        emit Locked(tokenId);
    }

    /** @dev Unlock the locked tokenId.
     *  @param tokenId to unlock
     */
    function _unlock(uint256 tokenId) internal virtual {
        require(_exists(tokenId), "ERC721Lockable: nonexistent token");
        require(_locked[tokenId], "ERC721Lockable: invalid state");
        delete (_locked[tokenId]);
        emit Unlocked(tokenId);
    }

    function isLocked(uint256 tokenId) public view override returns (bool) {
        return _locked[tokenId];
    }

    /** @dev Reverts If the tokenId is locked
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        require(!_locked[tokenId], "ERC721Lockable: transfer state error");
        super._beforeTokenTransfer(from, to, tokenId);
    }
}


abstract contract ERC721Burnable is Context, ERC721 {
    /**
     * @dev Burns `tokenId`. See {ERC721-_burn}.
     *
     * Requirements:
     *
     * - The caller must own `tokenId` or be an approved operator.
     */
    function burn(uint256 tokenId) public virtual {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: caller is not token owner nor approved");
        _burn(tokenId);
    }
}


abstract contract ERC721URIStorage is ERC721 {
    using Strings for uint256;

    // Optional mapping for token URIs
    mapping(uint256 => string) private _tokenURIs;

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        _requireMinted(tokenId);

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }

        return super.tokenURI(tokenId);
    }

    /**
     * @dev Sets `_tokenURI` as the tokenURI of `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_exists(tokenId), "ERC721URIStorage: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @dev See {ERC721-_burn}. This override additionally checks to see if a
     * token-specific URI was set for the token, and if so, it deletes the token URI from
     * the storage mapping.
     */
    function _burn(uint256 tokenId) internal virtual override {
        super._burn(tokenId);

        if (bytes(_tokenURIs[tokenId]).length != 0) {
            delete _tokenURIs[tokenId];
        }
    }
}


interface IURC721 is IERC721Metadata {
    function mint(address to, uint tokenId, string calldata tokenURI) external;
    function mintAuto(address to, string calldata tokenURI) external;
    function burn(uint tokenId) external;
    function lastId() external view returns (uint tokenId);
    function nextId() external view returns (uint tokenId);
}

abstract contract RiskGuard is Context {
    using CommonDataFormat for CommonDataFormat.CommonData;

    // the contract mananging request risk
    address immutable public riskManager; 

    constructor(address riskManager_) {
        require(riskManager_.code.length > 0 && address(riskManager_) != address(0), "RiskGuard: only contract");
        riskManager = riskManager_;
    }
    /**
     * @dev Checks for risks associated with a single address before executing the function.
     * 
     * The caller's address is inherently included in the risk check.
     * 
     * TIP: It is used when there is only one address related to the function call, excluding the caller.
     */
    modifier nonRisk(bytes4 selector, address account) {
        if(account != _msgSender()) _isRiskedRequests(selector, _makeArray(account));
        else _isRiskedRequest(selector, account);
        _;
    }
    
    /**
     * @dev Checks for risks associated with addresses before executing the function.
     * 
     * The caller's address is inherently included in the risk check.
     * 
     * TIP: "It is used when there are two addresses related to the function call, excluding the caller
     *      : one for `from` and another for `to`.
     */
    modifier nonRisks(bytes4 selector, address from, address to) {
        _isRiskedRequests(selector, _makeArray(from, to));
        _;
    }

    /**
     * @dev Call `RiskManager` for requests. (false: not exist risk, true: exist risk)
     *      If it exists risk, revert it.
     * @param selector function signature to detect risk
     * @param accounts the addresses to inspect for risk
     */
    function _isRiskedRequests(bytes4 selector, address[] memory accounts) internal view {
        require(
            !IRiskManager(riskManager).isRiskedRequests(
                CommonDataFormat.dataVersion(),
                _getCommonFormatBytes(selector, accounts)
            ), "RiskGuard: risked request"
        );
    }

    /**
     * @dev Call `RiskManager` for a request. (false: not exist risk, true: exist risk)
     *      If it exists risk, revert it.
     * @param selector function selector to inspect for risk
     * @param account the address to inspect for risk
     */
    function _isRiskedRequest(bytes4 selector, address account) internal view {
        require(
            !IRiskManager(riskManager).isRiskedRequest(
                CommonDataFormat.dataVersion(),
                CommonDataFormat.encodeToCommonFormat(CommonDataFormat.CommonData(selector, address(this), account, _msgSender()))
            ), "RiskGuard: risked request"
        );
    }

    /**
     * @dev To enable the `RiskManager` to handle requests for risk assessment 
     *      for multiple addresses, it converts them into bytes format.
     * @param selector function selector to inspect for risk
     * @param accounts the addresses to inspect for risk
     * 
     */
    function _getCommonFormatBytes(
        bytes4 selector, 
        address[] memory accounts
    ) internal view returns(bytes[] memory) {
        bytes[] memory request = new bytes[](accounts.length);
        address  sender = _msgSender();
        for (uint i; i < accounts.length; ) {
            request[i] = CommonDataFormat.encodeToCommonFormat(
                CommonDataFormat.CommonData(selector, address(this), accounts[i], sender)
            );
            unchecked{ i++; }
        }
            
        return request;
    }

    /**
     * @dev Creating a data format for the `RiskManager` call.
     */
    function _makeArray (
        address from, 
        address to
    ) internal view returns(address[] memory _addressArray) {
        _addressArray = new address[](3);
        _addressArray[0] = _msgSender();
        _addressArray[1] = from;
        _addressArray[2] = to;
    }

    /**
     * @dev Creating a data format for the `RiskManager` call.
     */
    function _makeArray (
        address to
    ) internal view returns(address[] memory _addressArray) {
        _addressArray = new address[](2);
        _addressArray[0] = _msgSender();
        _addressArray[1] = to;
    }
}

contract NightCrowBase is Ownable {
    //===== VARIABLES =====//
    address public roleManager;
    bytes32 constant public setterRole = "NightCrowSetter";
    bytes32 constant public validatorRole = "NightCrowValidator";

    //===== MODIFIERS =====//
    modifier onlyValidRole(bytes32 role) {
        require(_msgSender() == owner() || _hasRole(role, msg.sender),
            "NightCrow: sender has not the role"
        );
        _;
    }

    modifier onlyCA(address addr) {
        require(addr != address(0) && addr.code.length > 0,
            "NightCrow: address is not CA"
        );
        _;
    }

    //===== CONSTRUCTOR =====//
    constructor(address _roleManager) {
        setRoleManager(_roleManager);
    }

    //===== FUNCTIONS =====//
    function setRoleManager(address _roleManager) public onlyValidRole(setterRole) onlyCA(_roleManager) {
        roleManager = _roleManager;
    }

    function _hasRole(bytes32 role, address addr) internal view returns (bool) {
        return IRoleManager(roleManager).hasRole(role, addr);
    }
}

abstract contract VerifyKey is IVerifyKey {
    using Counters for Counters.Counter;

    mapping(bytes32 => bytes4) internal _functionSelectors;
    mapping(address => Counters.Counter) private _userNonce;

    function getVerifyKey(address user, bytes32 functionName) external virtual override view returns (bytes32) {
        return _getVerifyKey(user, _functionSelectors[functionName]);
    }

    function _getVerifyKey(address user, bytes4 selector) internal virtual view returns (bytes32) {
        address _user = user;
        // vault manager address, chainId, user address, user nonce
        return keccak256(abi.encodePacked(address(this), block.chainid, _user, selector, _userNonce[_user].current()));
    }

    function _renewSeed(address user) internal virtual {
        _userNonce[user].increment();
    }

    function _checkAlreadyRegistered(bytes32 functionName) internal virtual returns (bool) {
        return _functionSelectors[functionName] == bytes4(0);
    }

    function _registFunctionSelector(bytes32 functionName, bytes4 selector) internal virtual {
        bytes32 _functionName = functionName;
        require(_checkAlreadyRegistered(_functionName), "VerifyKey: already registered");
        _functionSelectors[_functionName] = selector;
    }
}

interface INightCrowEcho {
    enum TokenType {ERC20, ERC721, ERC1155}

    function echo(
        bytes32 requestID,
        bytes32 service,
        bytes32 token,
        TokenType tokenType,
        bytes4 selector,
        bool isSuccess,
        bytes32 message,
        uint blockNumber,
        uint deadline,
        bytes calldata callData
    ) external;
}


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


abstract contract URC721 is IURC721, ERC721Enumerable, ERC721Burnable, ERC721Lockable, ERC721URIStorage, RiskGuard {
    using UnaLib for uint;

    //===== VARIABLES =====//
    uint public immutable code;
    uint public constant unit = 1000000000;
    uint private _lastId;

    //===== MODIFIERS =====//
    modifier onlyBridge() {
        require(_checkBridge(_msgSender()), "Una721: sender is not bridge");
        _;
    }

    modifier onlyMinter() {
        require(_checkMinter(_msgSender()), "URC721: sender is not minter");
        _;
    }

    constructor(
        string memory name,
        string memory symbol,
        address riskManager,
        uint _code
    )
        ERC721(name, symbol)
        RiskGuard(riskManager)
    {
       require(_code % unit == 0, "URC721: invalid unit");
        code = _code;
    }

    //===== FUNCTIONS =====//
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
    function mint(
        address to,
        uint tokenId,
        string calldata _tokenURI
    )
        public
        virtual
        override
        onlyBridge
        nonRisk(this.mint.selector, to)
    {
        _mint(to, tokenId, _tokenURI);
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `tokenId` is automatically generated by a set rule (code + increamed number).
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function mintAuto(
        address to,
        string calldata _tokenURI
    )
        public
        virtual
        override
        onlyMinter
        nonRisk(this.mintAuto.selector, to)
    {
        _mintAuto(to, _tokenURI);
    }

    /**
     * @dev Burns `tokenId`. See {ERC721-_burn}.
     *
     * Requirements:
     *
     * - The caller must own `tokenId` or be an approved operator.
     */
    function burn(
        uint tokenId
    )
        public
        override(ERC721Burnable, IURC721)
        nonRisk(this.burn.selector, _msgSender())
    {
        super.burn(tokenId);
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        override(ERC721, IERC721)
        nonRisks(this.transferFrom.selector, from, to)
    {
        super.transferFrom(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    )
        public
        override(ERC721, IERC721)
        nonRisks(this.transferFrom.selector, from, to)
    {
        super.safeTransferFrom(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    )
        public
        override(ERC721, IERC721)
        nonRisks(this.transferFrom.selector, from, to)
    {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    /**
     *  @dev tokens list that owned by given owner
     *  @param owner owner of tokens
     */
    function tokensOfOwner(address owner) external view returns(uint[] memory tokenIds) {
        (tokenIds, ) = _tokensOfOwner(owner, false);
    }
    
    /**
     * @dev See next token id
     */
    function lastId() public view override returns (uint tokenId) {
        return generateId(_lastId);
    }

    /**
     * @dev See next token id
     */
    function nextId() public view override returns (uint tokenId) {
        return generateId(_lastId + 1);
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint tokenId)
        public
        view
        override(ERC721, ERC721URIStorage, IERC721Metadata)
        returns (string memory)
    {
       return super.tokenURI(tokenId);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(ERC721,ERC721Enumerable, IERC165)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev NFT is minted only from the specified code to the number of units.
     * @param id used to generate token id
     */
    function generateId(uint id) public view returns (uint tokenId) {
        require(id <= unit, "Una721: mint count is over");
        tokenId = code + id;
    }

    /**
     * @dev Reverts If the tokenId is locked
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint tokenId
    )
        internal
        virtual
        override(ERC721Lockable,ERC721Enumerable,ERC721)
    {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function _mint(
        address to,
        uint tokenId,
        string calldata _tokenURI
    )
        internal
    {
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
    }

    function _mintAuto(
        address to,
        string calldata _tokenURI
    )
        internal
        virtual
    {
        _lastId++;
        uint tokenId = generateId(_lastId);

        _mint(to, tokenId, _tokenURI);
    }

    function _burn(uint tokenId) internal virtual override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function _checkBridge(address sender) internal virtual view returns (bool) {}

    function _checkMinter(address sender) internal virtual view returns (bool) {}

    function _tokensOfOwner(address owner, bool lockedOption) internal view returns (uint[] memory tokenIds, uint lockedCount) {
        uint balance = ERC721.balanceOf(owner);

        tokenIds = new uint[](balance);

        unchecked {
            for(uint i = 0; i < balance; i++) {
                uint tokenId = tokenOfOwnerByIndex(owner, i);
                
                if(lockedOption) {
                    if(!isLocked(tokenId)) continue;
                    lockedCount++;
                }

                tokenIds[i] = tokenId;
            }
        }
    }
}

enum State {SEAL, PLAY}

interface INightCrowNFT {    
    function seal(
        uint tokenId,
        uint deadline,
        bytes calldata validatorSig
    ) external;

    function unseal(
        uint tokenId,
        uint deadline,
        bytes calldata validatorSig
    ) external;

    function mintItem(
        string calldata tokenURI,
        bool isUnseal,
        uint deadline,
        bytes calldata validatorSig
    ) external;

    function mintItemByValidator(
        address[] memory tos,
        string[] calldata tokenURIs,
        bool[] memory isUnseals
    ) external;

    function stateOf(uint tokenId) external view returns (State);
    function isPlay(uint tokenId) external view returns (bool);
}

abstract contract NightCrowUnaBase is NightCrowBase, VerifyKey {
    using UnaLib for uint;
    using ECDSA for bytes32;
    
    //===== VARIABLES =====//
    address public nightCrowEcho;
    bytes32 public constant success = "success";

    //===== CONSTRUCTOR =====//
    constructor(
        address roleManager,
        address _nightCrowEcho
    )
        NightCrowBase(roleManager)
    {
        setNightCrowEcho(_nightCrowEcho);
    }

    //===== FUNCTIONS =====//
    function setNightCrowEcho(
        address _nightCrowEcho
    ) public onlyValidRole(setterRole) onlyCA(_nightCrowEcho) {
        nightCrowEcho = _nightCrowEcho;
    }

    function getRequestID(
        address addr,
        bytes calldata data,
        address sender
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(addr, data, sender));
    }

    function _echo(
        bytes32 requestID,
        bytes32 service,
        bytes32 token,
        INightCrowEcho.TokenType tokenType,
        bytes4 selector,
        bool isSuccess,
        bytes32 message,
        uint deadline,
        bytes memory callData
    ) internal {
        INightCrowEcho(nightCrowEcho).echo(
            requestID,
            service,
            token,
            tokenType,
            selector,
            isSuccess,
            message,
            block.chainid.blockNumber(),
            deadline,
            callData
        );
    }

    function _checkValidSig(
        bytes32 role,
        bytes memory data,
        bytes memory signature
    ) internal view returns (bool isSuccess, bytes32 message) {
        address recover = keccak256(data).recover(signature);
        (isSuccess, message) = _hasRole(role, recover) ? (true, success) : (false, bytes32("invalid sig"));
    }

    function _checkDeadline(uint deadline) internal view returns (bool isSuccess, bytes32 message) {
        (isSuccess, message) = deadline >= block.chainid.blockNumber() || deadline == 0 ? (true, success) : (false, bytes32("over deadline"));
    }
}

contract NightCrowNFT is INightCrowNFT, URC721, NightCrowUnaBase {
    using ECDSA for bytes32;
    using Address for address;
    using Converter for string;

    //===== VARIABLES =====//
    mapping(uint => State) public override stateOf;    // state of the NFT

    bytes4 public constant sealSelector = INightCrowNFT.seal.selector;
    bytes4 public constant unsealSelector = INightCrowNFT.unseal.selector;
    bytes4 public constant mintItemSelector = INightCrowNFT.mintItem.selector;
    bytes4 public constant mintItemBVSelector = INightCrowNFT.mintItemByValidator.selector;

    bytes32 public constant service = "nightcrows";

    //===== MODIFIERS =====//
    modifier onlyTokenOwner(uint tokenId) {
        require(_msgSender() == ownerOf(tokenId), "NightCrowNFT: sender is not NFT's owner");
        _;
    }

    //===== EVENTS =====//
    event Sealed(address indexed _owner, uint indexed tokenId);
    event Unsealed(address indexed _owner, uint indexed tokenId);
    event ItemMinted(
        address indexed to,
        uint indexed tokenId,
        string tokenURI,
        State state
    );

    //===== CONSTRUCTOR =====//
    constructor(
        string memory name,
        string memory symbol,
        uint code,
        address roleManager,
        address riskManager,
        address nightCrowEcho
    )
        URC721(name, symbol, riskManager, code)
        NightCrowUnaBase(roleManager, nightCrowEcho)
    {
        _registFunctionSelector("seal", sealSelector);
        _registFunctionSelector("unseal", unsealSelector);
        _registFunctionSelector("mintItem", mintItemSelector);
        _registFunctionSelector("mintItemByValidator", mintItemBVSelector);
    }

    //===== MAIN FUNCTIONS =====//
    /** 
     * @dev Seals NFT unusable as game items.
     * @param tokenId to seal
     * @param deadline  deadline that this tx can be excuted
     * @param validatorSig Signature value for final confirmation if the NFT is actually an item of 'server'
     * signature (address(this), user, tokenId, deadline, server, verifyKey)
     */
    function seal(
        uint tokenId,
        uint deadline,
        bytes calldata validatorSig
    )
        external
        override
        nonRisk(sealSelector, _msgSender())
    {
        _toggle(
            tokenId,
            deadline,
            sealSelector,
            validatorSig
        );
    }

    /** 
     * @dev Unseal NFT for use as game items.
     * @param tokenId to unseal
     * @param deadline  deadline that this tx can be excuted
     * @param validatorSig Signature value for final confirmation if the NFT is actually an item of 'server'
     * signature (address(this), user, tokenId, deadline, server, verifyKey)
     */
    function unseal(
        uint tokenId,
        uint deadline,
        bytes calldata validatorSig
    )
        external
        override
        nonRisk(unsealSelector, _msgSender())
    {
        _toggle(
            tokenId,
            deadline,
            unsealSelector,
            validatorSig
        );
    }

    /**
    * @dev Mints `tokenId` and transfers it to `to`.
    * @param to  address to mint
    * @param tokenId  id of the NFT
    * @param tokenURI token uri of the NFT
    */
    function mint(
        address to,
        uint tokenId,
        string calldata tokenURI
    )
        public
        override
    {
        super.mint(to, tokenId, tokenURI);
        stateOf[tokenId] = State.SEAL;
    }

    /**
    * @dev Mints `tokenId` and transfers it to `to`.
    * @param to  address to mint
    * @param tokenURI token uri of the NFT
    */
    function mintAuto(
        address to,
        string calldata tokenURI
    )
        public
        override
    {
        super.mintAuto(to, tokenURI);
        stateOf[lastId()] = State.SEAL;
    }

     /**
    * @dev Mints `tokenId` and transfers it to `to` with the server name
    * @param tokenURI token uri of the NFT
    * @param isUnseal check the nft's state is unseal or seal
    * @param deadline  deadline that this tx can be excuted
    * @param validatorSig signature value for final confirmation if the NFT minted to the 'server' as item
     * signature (address(this), user, tokenURI, server, isUnseal deadline, verifyKey)
    */
    function mintItem(
        string calldata tokenURI,
        bool isUnseal,
        uint deadline,
        bytes calldata validatorSig
    )
        external
        override
        nonRisk(mintItemSelector, _msgSender())
    {
        address user = _msgSender();
        // avoid stack too deep
        string calldata _tokenURI = tokenURI;
        bool _isUnseal = isUnseal;
        uint _deadline = deadline;
        bytes calldata _validatorSig = validatorSig;

        (bool isSuccess, bytes32 message) = _checkData(
            user,
            _tokenURI,
            _isUnseal,
            _deadline,
            _validatorSig
        );

        if (isSuccess) _mintItem(user, _tokenURI, _isUnseal);

        bytes32 requestID = getRequestID(address(this), msg.data, user);
        
        _echo(
            requestID,
            service,
            symbol().stringToBytes32(),
            INightCrowEcho.TokenType.ERC721,
            mintItemSelector,
            isSuccess,
            message,
            _deadline,
            ""
        );
    }

    /**
    * @dev External function that generates as many token IDs as 'num'.
    * @param tos  address to mint
    * @param tokenURIs token uris of the NFT
    * @param isUnseals check the nft's state is unseal or seal
    */
    function mintItemByValidator(
        address[] memory tos,
        string[] calldata tokenURIs,
        bool[] memory isUnseals
    )
        external
        onlyValidRole(validatorRole)
    {
        require(
            tos.length == tokenURIs.length && tokenURIs.length == isUnseals.length,
            "NigthCrowNFT: invalid length"
        );
        
        _isRiskedRequests(mintItemBVSelector, tos);

        for (uint i = 0; i < tokenURIs.length;) {
            _mintItem(tos[i], tokenURIs[i], isUnseals[i]);
            unchecked { i++; }
        }
    }

    //===== VIEW FUNCTIONS =====//
    /**
     * @dev Check the NFT's state is 'PLAY'
     * The game server manages the NFT so that it can only be used in the game when the State is 'PLAY'.
     * @param tokenId to check state is 'PLAY'
     */
    function isPlay(uint tokenId) public override view returns (bool) {
        return stateOf[tokenId] == State.PLAY;
    }

    //===== INTERNAL FUNCTIONS =====//
    function _toggle(
        uint tokenId,
        uint deadline,
        bytes4 selector,
        bytes calldata validatorSig
    )
        private
    {
        address user = _msgSender();
        uint _tokenId = tokenId;
        uint _deadline = deadline;
        bytes4 _selector = selector;
        bytes calldata _validatorSig = validatorSig;
        bytes32 requestID = getRequestID(address(this), msg.data, _msgSender());
        
        (bool isSuccess, bytes32 message) = _checkData(
            user,
            _tokenId,
            _deadline,
            _selector,
            _validatorSig
        );

        if (isSuccess) {
            if (_selector == sealSelector) {
                _unlock(_tokenId);
                stateOf[_tokenId] = State.SEAL;

                emit Sealed(user, _tokenId);
            } else {
                _lock(_tokenId);
                stateOf[_tokenId] = State.PLAY;

                emit Unsealed(user, _tokenId);
            }
        }

        _echo(
            requestID,
            service,
            symbol().stringToBytes32(),
            INightCrowEcho.TokenType.ERC721,
            _selector,
            isSuccess,
            message,
            _deadline,
            ""
        );
    }

    function _mintItem(
        address to,
        string calldata tokenURI,
        bool isUnseal
    )
        private
    {
        super._mintAuto(to, tokenURI);
        uint tokenId = lastId();

        if (isUnseal) {
            _lock(tokenId);
            stateOf[tokenId] = State.PLAY;
        }

        emit ItemMinted(to, tokenId, tokenURI, stateOf[tokenId]);
    }

    function _checkBridge(address sender) internal virtual override view returns (bool) {
        return _hasRole(symbol().concat("Bridge"), sender) && sender.code.length > 0;
    }

    function _checkMinter(address sender) internal virtual override view returns (bool) {
       return sender == owner() || _hasRole(symbol().concat("Minter"), sender);
    }

    function _checkData(
        address user,
        uint tokenId,
        uint deadline,
        bytes4 selector,
        bytes calldata validatorSig
    )
        private
        returns (bool isSuccess, bytes32 message)
    {
        bytes32 verifyKey = _getVerifyKey(user, selector);
        _renewSeed(user);

        (isSuccess, message) = _checkOwner(user, tokenId);
        if (!isSuccess) return (isSuccess, message);

        (isSuccess, message) = _checkDeadline(deadline);
        if (!isSuccess) return (isSuccess, message);

        (isSuccess, message) = _checkState(tokenId, selector);
        if (!isSuccess) return (isSuccess, message);

        (isSuccess, message) = _checkValidSig(
            validatorRole,
            abi.encodePacked(
                address(this),
                user,
                tokenId,
                deadline,
                verifyKey
            ),
            validatorSig
        );

        if (!isSuccess) return (isSuccess, message);
    }

    function _checkData(
        address user,
        string calldata tokenURI,
        bool isUnseal,
        uint deadline,
        bytes calldata validatorSig
    )
        private
        returns (bool isSuccess, bytes32 message)
    {
        bytes32 verifyKey = _getVerifyKey(user, mintItemSelector);
        _renewSeed(user);

        (isSuccess, message) = _checkDeadline(deadline);
        if (!isSuccess) return (isSuccess, message);

        (isSuccess, message) = _checkValidSig(
            validatorRole,
            abi.encodePacked(
                address(this),
                user,
                tokenURI,
                isUnseal,
                deadline,
                verifyKey
            ),
            validatorSig
        );
        
        if (!isSuccess) return (isSuccess, message);
    }

    function _checkOwner(address user, uint tokenId) private view returns (bool isSuccess, bytes32 message) {
        (isSuccess, message) = user == ownerOf(tokenId)? (true, success) : (false, bytes32("sender is not NFT's owner"));
    }
    
    function _checkState(uint tokenId, bytes4 selector) private view returns (bool isSuccess, bytes32 message) {
        if (selector == sealSelector) {
            (isSuccess, message) = isPlay(tokenId) ? (true, success) : (false, bytes32("state is already SEAL"));
        } else {
            (isSuccess, message) = !isPlay(tokenId) ? (true, success) : (false, bytes32("state is already PLAY"));
        }
    }

    function _checkRole(address sender, bytes32 role) private view returns (bool) {
        return sender == owner() || (_hasRole(role, sender) && sender.code.length > 0);
    }
}

contract NCCHA is NightCrowNFT {
    constructor(
        string memory name,
        string memory symbol,
        uint code,
        address roleManager,
        address riskManager,
        address nightCrowEcho
    ) NightCrowNFT(
        name,
        symbol,
        code,
        roleManager,
        riskManager,
        nightCrowEcho
    ) {}
}
