// Sources flattened with hardhat v2.11.2 https://hardhat.org

// File contracts/core/interfaces/IERC677Receiver.sol

// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.15;

interface IERC677Receiver {
    function onTokenTransfer(
        address _sender,
        uint256 _value,
        bytes calldata _data
    ) external;
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}


// File @openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.5.0) (utils/Address.sol)

pragma solidity ^0.8.1;

/**
 * @dev Collection of functions related to the address type
 */
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


// File @openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.6.0) (proxy/utils/Initializable.sol)

pragma solidity ^0.8.2;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since proxied contracts do not make use of a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * The initialization functions use a version number. Once a version number is used, it is consumed and cannot be
 * reused. This mechanism prevents re-execution of each "step" but allows the creation of new initialization steps in
 * case an upgrade adds a module that needs to be initialized.
 *
 * For example:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * contract MyToken is ERC20Upgradeable {
 *     function initialize() initializer public {
 *         __ERC20_init("MyToken", "MTK");
 *     }
 * }
 * contract MyTokenV2 is MyToken, ERC20PermitUpgradeable {
 *     function initializeV2() reinitializer(2) public {
 *         __ERC20Permit_init("MyToken");
 *     }
 * }
 * ```
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 *
 * [CAUTION]
 * ====
 * Avoid leaving a contract uninitialized.
 *
 * An uninitialized contract can be taken over by an attacker. This applies to both a proxy and its implementation
 * contract, which may impact the proxy. To prevent the implementation contract from being used, you should invoke
 * the {_disableInitializers} function in the constructor to automatically lock it when it is deployed:
 *
 * [.hljs-theme-light.nopadding]
 * ```
 * /// @custom:oz-upgrades-unsafe-allow constructor
 * constructor() {
 *     _disableInitializers();
 * }
 * ```
 * ====
 */
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
     * `onlyInitializing` functions can be used to initialize parent contracts. Equivalent to `reinitializer(1)`.
     */
    modifier initializer() {
        bool isTopLevelCall = _setInitializedVersion(1);
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
     * `initializer` is equivalent to `reinitializer(1)`, so a reinitializer may be used after the original
     * initialization step. This is essential to configure modules that are added through upgrades and that require
     * initialization.
     *
     * Note that versions can jump in increments greater than 1; this implies that if multiple reinitializers coexist in
     * a contract, executing them in the right order is up to the developer or operator.
     */
    modifier reinitializer(uint8 version) {
        bool isTopLevelCall = _setInitializedVersion(version);
        if (isTopLevelCall) {
            _initializing = true;
        }
        _;
        if (isTopLevelCall) {
            _initializing = false;
            emit Initialized(version);
        }
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
     */
    function _disableInitializers() internal virtual {
        _setInitializedVersion(type(uint8).max);
    }

    function _setInitializedVersion(uint8 version) private returns (bool) {
        // If the contract is initializing we ignore whether _initialized is set in order to support multiple
        // inheritance patterns, but we only do this in the context of a constructor, and for the lowest level
        // of initializers, because in other contexts the contract may have been reentered.
        if (_initializing) {
            require(
                version == 1 && !AddressUpgradeable.isContract(address(this)),
                "Initializable: contract is already initialized"
            );
            return false;
        } else {
            require(_initialized < version, "Initializable: contract is already initialized");
            _initialized = version;
            return true;
        }
    }
}


// File @openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol@v4.6.0


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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal onlyInitializing {
    }

    function __Context_init_unchained() internal onlyInitializing {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/IERC20Metadata.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;




/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal onlyInitializing {
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal onlyInitializing {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;
}


// File contracts/core/tokens/base/ERC677Upgradeable.sol


pragma solidity 0.8.15;

contract ERC677Upgradeable is ERC20Upgradeable {
    function __ERC677_init(
        string memory _tokenName,
        string memory _tokenSymbol,
        uint256 _totalSupply
    ) public onlyInitializing {
        __ERC20_init(_tokenName, _tokenSymbol);
        _mint(msg.sender, _totalSupply * (10**uint256(decimals())));
    }

    function transferAndCall(
        address _to,
        uint256 _value,
        bytes memory _data
    ) public returns (bool) {
        super.transfer(_to, _value);
        if (isContract(_to)) {
            contractFallback(msg.sender, _to, _value, _data);
        }
        return true;
    }

    function transferAndCallFrom(
        address _sender,
        address _to,
        uint256 _value,
        bytes memory _data
    ) internal returns (bool) {
        _transfer(_sender, _to, _value);
        if (isContract(_to)) {
            contractFallback(_sender, _to, _value, _data);
        }
        return true;
    }

    function contractFallback(
        address _sender,
        address _to,
        uint256 _value,
        bytes memory _data
    ) internal {
        IERC677Receiver receiver = IERC677Receiver(_to);
        receiver.onTokenTransfer(_sender, _value, _data);
    }

    function isContract(address _addr) internal view returns (bool hasCode) {
        uint256 length;
        assembly {
            length := extcodesize(_addr)
        }
        return length > 0;
    }
}


// File @openzeppelin/contracts-upgradeable/interfaces/draft-IERC1822Upgradeable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.5.0) (interfaces/draft-IERC1822.sol)

pragma solidity ^0.8.0;

/**
 * @dev ERC1822: Universal Upgradeable Proxy Standard (UUPS) documents a method for upgradeability through a simplified
 * proxy whose upgrades are fully controlled by the current implementation.
 */
interface IERC1822ProxiableUpgradeable {
    /**
     * @dev Returns the storage slot that the proxiable contract assumes is being used to store the implementation
     * address.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy.
     */
    function proxiableUUID() external view returns (bytes32);
}


// File @openzeppelin/contracts-upgradeable/utils/StorageSlotUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts v4.4.1 (utils/StorageSlot.sol)

pragma solidity ^0.8.0;

/**
 * @dev Library for reading and writing primitive types to specific storage slots.
 *
 * Storage slots are often used to avoid storage conflict when dealing with upgradeable contracts.
 * This library helps with reading and writing to such slots without the need for inline assembly.
 *
 * The functions in this library return Slot structs that contain a `value` member that can be used to read or write.
 *
 * Example usage to set ERC1967 implementation slot:
 * ```
 * contract ERC1967 {
 *     bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
 *
 *     function _getImplementation() internal view returns (address) {
 *         return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
 *     }
 *
 *     function _setImplementation(address newImplementation) internal {
 *         require(Address.isContract(newImplementation), "ERC1967: new implementation is not a contract");
 *         StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
 *     }
 * }
 * ```
 *
 * _Available since v4.1 for `address`, `bool`, `bytes32`, and `uint256`._
 */
library StorageSlotUpgradeable {
    struct AddressSlot {
        address value;
    }

    struct BooleanSlot {
        bool value;
    }

    struct Bytes32Slot {
        bytes32 value;
    }

    struct Uint256Slot {
        uint256 value;
    }

    /**
     * @dev Returns an `AddressSlot` with member `value` located at `slot`.
     */
    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `BooleanSlot` with member `value` located at `slot`.
     */
    function getBooleanSlot(bytes32 slot) internal pure returns (BooleanSlot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Bytes32Slot` with member `value` located at `slot`.
     */
    function getBytes32Slot(bytes32 slot) internal pure returns (Bytes32Slot storage r) {
        assembly {
            r.slot := slot
        }
    }

    /**
     * @dev Returns an `Uint256Slot` with member `value` located at `slot`.
     */
    function getUint256Slot(bytes32 slot) internal pure returns (Uint256Slot storage r) {
        assembly {
            r.slot := slot
        }
    }
}


// File @openzeppelin/contracts-upgradeable/proxy/beacon/IBeaconUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts v4.4.1 (proxy/beacon/IBeacon.sol)

pragma solidity ^0.8.0;

/**
 * @dev This is the interface that {BeaconProxy} expects of its beacon.
 */
interface IBeaconUpgradeable {
    /**
     * @dev Must return an address that can be used as a delegate call target.
     *
     * {BeaconProxy} will check that this address is a contract.
     */
    function implementation() external view returns (address);
}


// File @openzeppelin/contracts-upgradeable/proxy/ERC1967/ERC1967UpgradeUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.5.0) (proxy/ERC1967/ERC1967Upgrade.sol)

pragma solidity ^0.8.2;





/**
 * @dev This abstract contract provides getters and event emitting update functions for
 * https://eips.ethereum.org/EIPS/eip-1967[EIP1967] slots.
 *
 * _Available since v4.1._
 *
 * @custom:oz-upgrades-unsafe-allow delegatecall
 */
abstract contract ERC1967UpgradeUpgradeable is Initializable {
    function __ERC1967Upgrade_init() internal onlyInitializing {
    }

    function __ERC1967Upgrade_init_unchained() internal onlyInitializing {
    }
    // This is the keccak-256 hash of "eip1967.proxy.rollback" subtracted by 1
    bytes32 private constant _ROLLBACK_SLOT = 0x4910fdfa16fed3260ed0e7147f7cc6da11a60208b5b9406d12a635614ffd9143;

    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Emitted when the implementation is upgraded.
     */
    event Upgraded(address indexed implementation);

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 implementation slot.
     */
    function _setImplementation(address newImplementation) private {
        require(AddressUpgradeable.isContract(newImplementation), "ERC1967: new implementation is not a contract");
        StorageSlotUpgradeable.getAddressSlot(_IMPLEMENTATION_SLOT).value = newImplementation;
    }

    /**
     * @dev Perform implementation upgrade
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeTo(address newImplementation) internal {
        _setImplementation(newImplementation);
        emit Upgraded(newImplementation);
    }

    /**
     * @dev Perform implementation upgrade with additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCall(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        _upgradeTo(newImplementation);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(newImplementation, data);
        }
    }

    /**
     * @dev Perform implementation upgrade with security checks for UUPS proxies, and additional setup call.
     *
     * Emits an {Upgraded} event.
     */
    function _upgradeToAndCallUUPS(
        address newImplementation,
        bytes memory data,
        bool forceCall
    ) internal {
        // Upgrades from old implementations will perform a rollback test. This test requires the new
        // implementation to upgrade back to the old, non-ERC1822 compliant, implementation. Removing
        // this special case will break upgrade paths from old UUPS implementation to new ones.
        if (StorageSlotUpgradeable.getBooleanSlot(_ROLLBACK_SLOT).value) {
            _setImplementation(newImplementation);
        } else {
            try IERC1822ProxiableUpgradeable(newImplementation).proxiableUUID() returns (bytes32 slot) {
                require(slot == _IMPLEMENTATION_SLOT, "ERC1967Upgrade: unsupported proxiableUUID");
            } catch {
                revert("ERC1967Upgrade: new implementation is not UUPS");
            }
            _upgradeToAndCall(newImplementation, data, forceCall);
        }
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        require(newAdmin != address(0), "ERC1967: new admin is the zero address");
        StorageSlotUpgradeable.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function _changeAdmin(address newAdmin) internal {
        emit AdminChanged(_getAdmin(), newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev The storage slot of the UpgradeableBeacon contract which defines the implementation for this proxy.
     * This is bytes32(uint256(keccak256('eip1967.proxy.beacon')) - 1)) and is validated in the constructor.
     */
    bytes32 internal constant _BEACON_SLOT = 0xa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d50;

    /**
     * @dev Emitted when the beacon is upgraded.
     */
    event BeaconUpgraded(address indexed beacon);

    /**
     * @dev Returns the current beacon.
     */
    function _getBeacon() internal view returns (address) {
        return StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value;
    }

    /**
     * @dev Stores a new beacon in the EIP1967 beacon slot.
     */
    function _setBeacon(address newBeacon) private {
        require(AddressUpgradeable.isContract(newBeacon), "ERC1967: new beacon is not a contract");
        require(
            AddressUpgradeable.isContract(IBeaconUpgradeable(newBeacon).implementation()),
            "ERC1967: beacon implementation is not a contract"
        );
        StorageSlotUpgradeable.getAddressSlot(_BEACON_SLOT).value = newBeacon;
    }

    /**
     * @dev Perform beacon upgrade with additional setup call. Note: This upgrades the address of the beacon, it does
     * not upgrade the implementation contained in the beacon (see {UpgradeableBeacon-_setImplementation} for that).
     *
     * Emits a {BeaconUpgraded} event.
     */
    function _upgradeBeaconToAndCall(
        address newBeacon,
        bytes memory data,
        bool forceCall
    ) internal {
        _setBeacon(newBeacon);
        emit BeaconUpgraded(newBeacon);
        if (data.length > 0 || forceCall) {
            _functionDelegateCall(IBeaconUpgradeable(newBeacon).implementation(), data);
        }
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function _functionDelegateCall(address target, bytes memory data) private returns (bytes memory) {
        require(AddressUpgradeable.isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return AddressUpgradeable.verifyCallResult(success, returndata, "Address: low-level delegate call failed");
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


// File @openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.5.0) (proxy/utils/UUPSUpgradeable.sol)

pragma solidity ^0.8.0;



/**
 * @dev An upgradeability mechanism designed for UUPS proxies. The functions included here can perform an upgrade of an
 * {ERC1967Proxy}, when this contract is set as the implementation behind such a proxy.
 *
 * A security mechanism ensures that an upgrade does not turn off upgradeability accidentally, although this risk is
 * reinstated if the upgrade retains upgradeability but removes the security mechanism, e.g. by replacing
 * `UUPSUpgradeable` with a custom implementation of upgrades.
 *
 * The {_authorizeUpgrade} function must be overridden to include access restriction to the upgrade mechanism.
 *
 * _Available since v4.1._
 */
abstract contract UUPSUpgradeable is Initializable, IERC1822ProxiableUpgradeable, ERC1967UpgradeUpgradeable {
    function __UUPSUpgradeable_init() internal onlyInitializing {
    }

    function __UUPSUpgradeable_init_unchained() internal onlyInitializing {
    }
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable state-variable-assignment
    address private immutable __self = address(this);

    /**
     * @dev Check that the execution is being performed through a delegatecall call and that the execution context is
     * a proxy contract with an implementation (as defined in ERC1967) pointing to self. This should only be the case
     * for UUPS and transparent proxies that are using the current contract as their implementation. Execution of a
     * function through ERC1167 minimal proxies (clones) would not normally pass this test, but is not guaranteed to
     * fail.
     */
    modifier onlyProxy() {
        require(address(this) != __self, "Function must be called through delegatecall");
        require(_getImplementation() == __self, "Function must be called through active proxy");
        _;
    }

    /**
     * @dev Check that the execution is not being performed through a delegate call. This allows a function to be
     * callable on the implementing contract but not through proxies.
     */
    modifier notDelegated() {
        require(address(this) == __self, "UUPSUpgradeable: must not be called through delegatecall");
        _;
    }

    /**
     * @dev Implementation of the ERC1822 {proxiableUUID} function. This returns the storage slot used by the
     * implementation. It is used to validate that the this implementation remains valid after an upgrade.
     *
     * IMPORTANT: A proxy pointing at a proxiable contract should not be considered proxiable itself, because this risks
     * bricking a proxy that upgrades to it, by delegating to itself until out of gas. Thus it is critical that this
     * function revert if invoked through a proxy. This is guaranteed by the `notDelegated` modifier.
     */
    function proxiableUUID() external view virtual override notDelegated returns (bytes32) {
        return _IMPLEMENTATION_SLOT;
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeTo(address newImplementation) external virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, new bytes(0), false);
    }

    /**
     * @dev Upgrade the implementation of the proxy to `newImplementation`, and subsequently execute the function call
     * encoded in `data`.
     *
     * Calls {_authorizeUpgrade}.
     *
     * Emits an {Upgraded} event.
     */
    function upgradeToAndCall(address newImplementation, bytes memory data) external payable virtual onlyProxy {
        _authorizeUpgrade(newImplementation);
        _upgradeToAndCallUUPS(newImplementation, data, true);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
     * {upgradeTo} and {upgradeToAndCall}.
     *
     * Normally, this function will use an xref:access.adoc[access control] modifier such as {Ownable-onlyOwner}.
     *
     * ```solidity
     * function _authorizeUpgrade(address) internal override onlyOwner {}
     * ```
     */
    function _authorizeUpgrade(address newImplementation) internal virtual;

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}


// File @openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal onlyInitializing {
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal onlyInitializing {
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

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[49] private __gap;
}


// File contracts/core/base/StakingRewardsPool.sol


pragma solidity 0.8.15;


/**
 * @title StakingRewardsPool
 * @notice Handles staking and reward distribution for a single asset
 * @dev Rewards can be positive or negative (user balances can increase and decrease)
 */
abstract contract StakingRewardsPool is ERC677Upgradeable, UUPSUpgradeable, OwnableUpgradeable {
    IERC20Upgradeable public token;

    mapping(address => uint256) private shares;
    uint256 public totalShares;

    function __StakingRewardsPool_init(
        address _token,
        string memory _derivativeTokenName,
        string memory _derivativeTokenSymbol
    ) public onlyInitializing {
        __ERC677_init(_derivativeTokenName, _derivativeTokenSymbol, 0);
        __UUPSUpgradeable_init();
        __Ownable_init();
        token = IERC20Upgradeable(_token);
    }

    /**
     * @notice returns the total supply of staking derivative tokens
     * @return total supply
     */
    function totalSupply() public view override returns (uint256) {
        return _totalStaked();
    }

    /**
     * @notice returns an account's stake balance
     * @param _account account address
     * @return account's stake balance
     **/
    function balanceOf(address _account) public view override returns (uint256) {
        uint256 balance = getStakeByShares(shares[_account]);
        if (balance < 100) {
            return 0;
        } else {
            return balance;
        }
    }

    /**
     * @notice returns an account's share balance
     * @param _account account address
     * @return account's share balance
     **/
    function sharesOf(address _account) public view returns (uint256) {
        return shares[_account];
    }

    /**
     * @notice returns the amount of shares that corresponds to a staked amount
     * @param _amount staked amount
     * @return amount of shares
     **/
    function getSharesByStake(uint256 _amount) public view returns (uint256) {
        uint256 totalStaked = _totalStaked();
        if (totalStaked == 0) {
            return 0;
        } else {
            return (_amount * totalShares) / totalStaked;
        }
    }

    /**
     * @notice returns the amount of stake that corresponds to an amount of shares
     * @param _amount shares amount
     * @return amount of stake
     **/
    function getStakeByShares(uint256 _amount) public view returns (uint256) {
        if (totalShares == 0) {
            return 0;
        } else {
            return (_amount * _totalStaked()) / totalShares;
        }
    }

    /**
     * @notice returns the total amount of assets staked in the pool
     * @return total staked amount
     */
    function _totalStaked() internal view virtual returns (uint256);

    /**
     * @notice transfers a stake balance from one account to another
     * @param _sender account to transfer from
     * @param _recipient account to transfer to
     * @param _amount amount to transfer
     **/
    function _transfer(
        address _sender,
        address _recipient,
        uint256 _amount
    ) internal override {
        uint256 sharesToTransfer = getSharesByStake(_amount);

        require(_sender != address(0), "Transfer from the zero address");
        require(_recipient != address(0), "Transfer to the zero address");
        require(shares[_sender] >= sharesToTransfer, "Transfer amount exceeds balance");

        shares[_sender] -= sharesToTransfer;
        shares[_recipient] += sharesToTransfer;

        emit Transfer(_sender, _recipient, _amount);
    }

    /**
     * @notice mints new shares to an account
     * @dev takes a stake amount and calculates the amount of shares it corresponds to
     * @param _recipient account to mint shares for
     * @param _amount stake amount
     **/
    function _mint(address _recipient, uint256 _amount) internal override {
        uint256 sharesToMint = getSharesByStake(_amount);
        if (sharesToMint == 0) {
            sharesToMint = _amount;
        }

        _mintShares(_recipient, sharesToMint);

        emit Transfer(address(0), _recipient, _amount);
    }

    /**
     * @notice mints new shares to an account
     * @param _recipient account to mint shares for
     * @param _amount shares amount
     **/
    function _mintShares(address _recipient, uint256 _amount) internal {
        require(_recipient != address(0), "Mint to the zero address");

        totalShares += _amount;
        shares[_recipient] += _amount;
    }

    /**
     * @notice burns shares belonging to an account
     * @dev takes a stake amount and calculates the amount of shares it corresponds to
     * @param _account account to burn shares for
     * @param _amount stake amount
     **/
    function _burn(address _account, uint256 _amount) internal override {
        uint256 sharesToBurn = getSharesByStake(_amount);

        require(_account != address(0), "Burn from the zero address");
        require(shares[_account] >= sharesToBurn, "Burn amount exceeds balance");

        totalShares -= sharesToBurn;
        shares[_account] -= sharesToBurn;

        emit Transfer(_account, address(0), _amount);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}


// File contracts/liquidSDIndex/interfaces/ILSDIndexAdapter.sol


pragma solidity 0.8.15;

interface ILSDIndexAdapter {
    /**
     * @notice returns the total amount deposits of this token in the index pool
     * @return total deposits amount
     */
    function getTotalDeposits() external view returns (uint256);

    /**
     * @notice returns the underlying amount that corresponds to the total deposits of this adapter's
     * token in the index pool
     * @return total underlying amount
     */
    function getTotalDepositsValue() external view returns (uint256);

    /**
     * @notice returns the underlying amount that corresponds to an LSD amount
     * @param _lsdAmount amount of LSD tokens
     * @return underlying amount
     */
    function getUnderlyingByLSD(uint256 _lsdAmount) external view returns (uint256);

    /**
     * @notice returns the LSD amount that corresponds to an underlying amount
     * @param _underlyingAmount underlying amount
     * @return LSD amount
     */
    function getLSDByUnderlying(uint256 _underlyingAmount) external view returns (uint256);

    /**
     * @notice returns the exchange rate between this token and the underlying token
     * @return exchange rate
     */
    function getExchangeRate() external view returns (uint256);
}


// File @openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol@v4.6.0


// OpenZeppelin Contracts v4.4.1 (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;


/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(
        IERC20Upgradeable token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20Upgradeable token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20Upgradeable token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}


// File @openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol@v4.6.0


// OpenZeppelin Contracts (last updated v4.5.0) (utils/math/Math.sol)

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library MathUpgradeable {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    /**
     * @dev Returns the ceiling of the division of two numbers.
     *
     * This differs from standard division with `/` in that it rounds up instead
     * of rounding down.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a / b + (a % b == 0 ? 0 : 1);
    }
}


// File contracts/liquidSDIndex/LiquidSDIndexPool.sol


pragma solidity 0.8.15;



/**
 * @title Liquid Staking Derivative Index Pool
 * @notice Issues a liquid staking derivative token that's backed by a basket of individual
 * liquid staking derivative tokens
 */
contract LiquidSDIndexPool is StakingRewardsPool {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct Fee {
        address receiver;
        uint256 basisPoints;
    }

    uint256 private constant BASIS_POINTS_TOTAL = 10000;

    address[] private lsdTokens;
    mapping(address => ILSDIndexAdapter) public lsdAdapters;

    mapping(address => uint256) private compositionTargets;
    uint256 public compositionTolerance;
    uint256 public compositionEnforcementThreshold;

    Fee[] private fees;
    uint256 public withdrawalFee;

    uint256 private totalStaked;

    bool public isPaused;

    event Deposit(address indexed account, address indexed token, uint256 amount);
    event Withdraw(address indexed account, address[] tokens, uint256[] amounts);
    event UpdateRewards(address indexed account, uint256 totalStaked, int rewardsAmount, uint256 totalFees);
    event AddLSDToken(address indexed lsdToken, address lsdAdapter, uint256[] compositionTargets);
    event RemoveLSDToken(address indexed lsdToken, uint256[] compositionTargets);
    event SetCompositionTargets(uint256[] compositionTargets);
    event SetCompositionTolerance(uint256 compositionTolerance);
    event SetCompositionEnforcementThreshold(uint256 compositionEnforcementThreshold);
    event SetWithdrawalFee(uint256 withdrawalFee);
    event AddFee(address indexed receiver, uint256 feeBasisPoints);
    event UpdateFee(address indexed receiver, uint256 feeBasisPoints);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _derivativeTokenName,
        string memory _derivativeTokenSymbol,
        uint256 _compositionTolerance,
        uint256 _compositionEnforcementThreshold,
        Fee[] calldata _fees,
        uint256 _withdrawalFee
    ) public initializer {
        __StakingRewardsPool_init(address(0), _derivativeTokenName, _derivativeTokenSymbol);
        setCompositionTolerance(_compositionTolerance);
        setCompositionEnforcementThreshold(_compositionEnforcementThreshold);
        setWithdrawalFee(_withdrawalFee);
        for (uint256 i = 0; i < _fees.length; i++) {
            fees.push(_fees[i]);
        }
        require(_totalFeesBasisPoints() <= 5000, "Total fees must be <= 50%");
    }

    modifier tokenIsSupported(address _lsdToken) {
        require(address(lsdAdapters[_lsdToken]) != address(0), "Token is not supported");
        _;
    }

    modifier notPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    /**
     * @notice returns a list of all supported lsd tokens
     * @return list of strategies
     */
    function getLSDTokens() external view returns (address[] memory) {
        return lsdTokens;
    }

    /**
     * @notice returns a list of all fees
     * @return list of fees
     */
    function getFees() external view returns (Fee[] memory) {
        return fees;
    }

    /**
     * @notice returns a list of basis point composition targets for each lsd
     * @return list of composition targets
     */
    function getCompositionTargets() external view returns (uint256[] memory) {
        uint256[] memory targets = new uint256[](lsdTokens.length);
        for (uint256 i = 0; i < lsdTokens.length; i++) {
            targets[i] = compositionTargets[lsdTokens[i]];
        }
        return targets;
    }

    /**
     * @notice returns the current basis point composition of deposits
     * @return list of compositions for each lsd
     */
    function getComposition() external view returns (uint256[] memory) {
        uint256 totalDeposits = _totalDeposits();
        uint256[] memory composition = new uint256[](lsdTokens.length);

        if (totalDeposits == 0) return composition;

        for (uint256 i = 0; i < composition.length; i++) {
            uint256 deposits = lsdAdapters[lsdTokens[i]].getTotalDeposits();
            composition[i] = (deposits * BASIS_POINTS_TOTAL) / totalDeposits;
        }

        return composition;
    }

    /**
     * @notice returns the deposit room for an lsd token
     * @param _lsdToken address of token
     * @return deposit room for token
     **/
    function getDepositRoom(address _lsdToken) public view tokenIsSupported(_lsdToken) returns (uint256) {
        uint256 depositLimit = type(uint256).max;
        uint256 depositsTotal;

        if (compositionTargets[_lsdToken] == 0) return 0;

        for (uint256 i = 0; i < lsdTokens.length; i++) {
            address lsdToken = lsdTokens[i];

            uint256 deposits = lsdAdapters[lsdToken].getTotalDeposits();
            depositsTotal += deposits;

            if (lsdToken == _lsdToken) continue;

            uint256 compositionTarget = compositionTargets[lsdToken];
            if (compositionTarget == 0) continue;

            // check how much can be deposited before the decrease in composition percentage exceeds the composition tolerance
            uint256 minComposition = compositionTarget - (compositionTarget * compositionTolerance) / BASIS_POINTS_TOTAL;
            depositLimit = MathUpgradeable.min((deposits * BASIS_POINTS_TOTAL) / minComposition, depositLimit);
        }

        uint256 depositTokenCompositionTarget = compositionTargets[_lsdToken];
        uint256 depositTokenDeposits = lsdAdapters[_lsdToken].getTotalDeposits();

        // check how much can be deposited before the increase in composition percentage exceeds the composition tolerance
        uint256 maxComposition = depositTokenCompositionTarget +
            (depositTokenCompositionTarget * compositionTolerance) /
            BASIS_POINTS_TOTAL;
        if (maxComposition < BASIS_POINTS_TOTAL) {
            depositLimit = MathUpgradeable.min(
                ((depositsTotal - depositTokenDeposits) * BASIS_POINTS_TOTAL) / (BASIS_POINTS_TOTAL - maxComposition),
                depositLimit
            );
        }

        // check if deposits are below the composition enforcement threshold and if so, use deposit room if it's greater
        // than the amount that could be deposited with enforcement of composition targets
        uint256 minThreshold = (compositionEnforcementThreshold * depositTokenCompositionTarget) / BASIS_POINTS_TOTAL;
        if (depositTokenDeposits < minThreshold) {
            uint256 thresholdDiff = minThreshold - depositTokenDeposits;
            depositLimit = MathUpgradeable.max(depositsTotal + thresholdDiff, depositLimit);
        }

        return depositLimit > depositsTotal ? depositLimit - depositsTotal : 0;
    }

    /**
     * @notice deposits lsd tokens and mints lsd index tokens
     * @param _lsdToken token to deposit
     * @param _amount amount to deposit
     **/
    function deposit(address _lsdToken, uint256 _amount) external tokenIsSupported(_lsdToken) notPaused {
        require(getDepositRoom(_lsdToken) >= _amount, "Insufficient deposit room for the selected lsd");

        ILSDIndexAdapter lsdAdapter = lsdAdapters[_lsdToken];

        uint256 underlyingAmount = lsdAdapter.getUnderlyingByLSD(_amount);
        require(underlyingAmount != 0, "Deposit amount too small");

        _mint(msg.sender, underlyingAmount);
        totalStaked += underlyingAmount;

        IERC20Upgradeable(_lsdToken).safeTransferFrom(msg.sender, address(lsdAdapter), _amount);

        emit Deposit(msg.sender, _lsdToken, _amount);
    }

    /**
     * @notice returns the amount of each lsd a withdrawer will receive for an amount of index tokens
     * @dev sender receives an amount of each lsd proportional to the size of the deposit gap
     * between each lsd's pre-withdrawal composition and its post-withdrawal target composition
     * (as a result, the current composition will move closer to the target after each withdrawal)
     * @param _amount amount to withdraw
     * @return list of lsd amounts
     **/
    function getWithdrawalAmounts(uint256 _amount) public view returns (uint256[] memory) {
        require(_amount <= totalStaked, "Cannot withdraw more than total staked amount");

        uint256[] memory withdrawalAmounts = new uint256[](lsdTokens.length);
        uint256[] memory targetDepositDiffs = new uint256[](lsdTokens.length);
        uint256 amount = _amount - _getWithdrawalFeeAmount(_amount);
        uint256 newTotalDeposits = _totalDeposits() - amount;
        uint256 totalTargetDepositDiffs;

        for (uint256 i = 0; i < targetDepositDiffs.length; i++) {
            uint256 newTargetDeposits = (newTotalDeposits * compositionTargets[lsdTokens[i]]) / BASIS_POINTS_TOTAL;
            uint256 currentDeposits = lsdAdapters[lsdTokens[i]].getTotalDeposits();
            int256 targetDepositDiff = int256(currentDeposits) - int256(newTargetDeposits);

            if (targetDepositDiff > 0) {
                targetDepositDiffs[i] = uint256(targetDepositDiff);
                totalTargetDepositDiffs += uint256(targetDepositDiff);
            }
        }

        for (uint256 i = 0; i < targetDepositDiffs.length; i++) {
            uint256 targetDepositDiff = targetDepositDiffs[i];

            if (targetDepositDiff > 0) {
                ILSDIndexAdapter lsdAdapter = lsdAdapters[lsdTokens[i]];
                uint256 withdrawalAmount = lsdAdapter.getLSDByUnderlying(
                    (amount * ((targetDepositDiff * 1e18) / totalTargetDepositDiffs)) / 1e18
                );
                withdrawalAmounts[i] = withdrawalAmount;
            }
        }

        return withdrawalAmounts;
    }

    /**
     * @notice withdraws lsd tokens and burns lsd index tokens
     * @param _amount amount to withdraw
     **/
    function withdraw(uint256 _amount) external notPaused {
        uint256[] memory withdrawalAmounts = getWithdrawalAmounts(_amount);

        _burn(msg.sender, _amount);
        totalStaked -= _amount - _getWithdrawalFeeAmount(_amount);

        for (uint256 i = 0; i < withdrawalAmounts.length; i++) {
            uint256 amount = withdrawalAmounts[i];
            if (amount != 0) {
                IERC20Upgradeable(lsdTokens[i]).safeTransferFrom(address(lsdAdapters[lsdTokens[i]]), msg.sender, amount);
            }
        }

        emit Withdraw(msg.sender, lsdTokens, withdrawalAmounts);
    }

    /**
     * @notice returns the amount of rewards earned since the last update and the amount of fees that
     * will be paid on the rewards
     * @return total rewards
     * @return total fees
     **/
    function getRewards() external view returns (int256, uint256) {
        int256 totalRewards = int256(_totalDeposits()) - int256(totalStaked);
        uint256 totalFees;

        if (totalRewards > 0) {
            for (uint256 i = 0; i < fees.length; i++) {
                totalFees += (uint256(totalRewards) * fees[i].basisPoints) / BASIS_POINTS_TOTAL;
            }
        }

        return (totalRewards, totalFees);
    }

    /**
     * @notice updates and distributes rewards based on balance changes in adapters
     **/
    function updateRewards() external notPaused {
        int256 totalRewards = int256(_totalDeposits()) - int256(totalStaked);

        if (totalRewards != 0) {
            totalStaked = uint256(int256(totalStaked) + totalRewards);
        }

        uint256 totalFeeAmounts;

        if (totalRewards > 0) {
            uint256[] memory feeAmounts = new uint256[](fees.length);

            for (uint256 i = 0; i < fees.length; i++) {
                feeAmounts[i] = (uint256(totalRewards) * fees[i].basisPoints) / BASIS_POINTS_TOTAL;
                totalFeeAmounts += feeAmounts[i];
            }

            if (totalFeeAmounts != 0) {
                uint256 sharesToMint = (totalFeeAmounts * totalShares) / (totalStaked - totalFeeAmounts);
                _mintShares(address(this), sharesToMint);

                for (uint256 i = 0; i < fees.length; i++) {
                    if (i == fees.length - 1) {
                        transferAndCallFrom(address(this), fees[i].receiver, balanceOf(address(this)), "0x00");
                    } else {
                        transferAndCallFrom(address(this), fees[i].receiver, feeAmounts[i], "0x00");
                    }
                }
            }
        }

        emit UpdateRewards(msg.sender, totalStaked, totalRewards, totalFeeAmounts);
    }

    /**
     * @notice adds a new liquid staking derivative token
     * @param _lsdToken address of token
     * @param _lsdAdapter address of token adapter
     * @param _compositionTargets basis point composition targets for each lsd
     **/
    function addLSDToken(
        address _lsdToken,
        address _lsdAdapter,
        uint256[] calldata _compositionTargets
    ) external onlyOwner {
        require(address(lsdAdapters[_lsdToken]) == address(0), "Token is already supported");
        require(_compositionTargets.length == lsdTokens.length + 1, "Invalid composition targets length");

        lsdTokens.push(_lsdToken);
        lsdAdapters[_lsdToken] = ILSDIndexAdapter(_lsdAdapter);

        uint256 totalComposition;
        for (uint256 i = 0; i < _compositionTargets.length; i++) {
            compositionTargets[lsdTokens[i]] = _compositionTargets[i];
            totalComposition += _compositionTargets[i];
        }

        require(totalComposition == BASIS_POINTS_TOTAL, "Composition targets must sum to 100%");
        emit AddLSDToken(_lsdToken, _lsdAdapter, _compositionTargets);
    }

    /**
     * @notice removes a liquid staking derivative token
     * @param _lsdToken address of token
     * @param _compositionTargets basis point composition targets for each remaining lsd
     **/
    function removeLSDToken(address _lsdToken, uint256[] calldata _compositionTargets)
        external
        onlyOwner
        tokenIsSupported(_lsdToken)
    {
        require(_compositionTargets.length == lsdTokens.length - 1, "Invalid composition targets length");
        require(lsdAdapters[_lsdToken].getTotalDeposits() < 1 ether, "Cannot remove adapter that contains deposits");

        uint256 index;
        for (uint256 i = 0; i < lsdTokens.length; i++) {
            if (lsdTokens[i] == _lsdToken) {
                index = i;
                break;
            }
        }

        for (uint256 i = index; i < lsdTokens.length - 1; i++) {
            lsdTokens[i] = lsdTokens[i + 1];
        }

        lsdTokens.pop();
        delete lsdAdapters[_lsdToken];

        uint256 totalComposition;
        for (uint256 i = 0; i < _compositionTargets.length; i++) {
            compositionTargets[lsdTokens[i]] = _compositionTargets[i];
            totalComposition += _compositionTargets[i];
        }

        require(totalComposition == BASIS_POINTS_TOTAL, "Composition targets must sum to 100%");
        emit RemoveLSDToken(_lsdToken, _compositionTargets);
    }

    /**
     * @notice sets composition targets
     * @param _compositionTargets list of basis point composition targets
     **/
    function setCompositionTargets(uint256[] calldata _compositionTargets) external onlyOwner {
        require(_compositionTargets.length == lsdTokens.length, "Invalid composition targets length");

        uint256 totalComposition;
        for (uint256 i = 0; i < _compositionTargets.length; i++) {
            compositionTargets[lsdTokens[i]] = _compositionTargets[i];
            totalComposition += _compositionTargets[i];
        }

        require(totalComposition == BASIS_POINTS_TOTAL, "Composition targets must sum to 100%");
        emit SetCompositionTargets(_compositionTargets);
    }

    /**
     * @notice sets composition tolerance
     * @dev the composition tolerance is the percentage swing that any lsd can have from its
     * composition target in either direction (if the composition tolerance was 50% and an lsd had a
     * composition target of 30%, then its minimum composition of the pool is 15% of deposits and its maximum is 45%)
     * @param _compositionTolerance basis point composition tolerance
     **/
    function setCompositionTolerance(uint256 _compositionTolerance) public onlyOwner {
        require(_compositionTolerance < BASIS_POINTS_TOTAL, "Composition tolerance must be < 100%");
        compositionTolerance = _compositionTolerance;
        emit SetCompositionTolerance(_compositionTolerance);
    }

    /**
     * @notice sets composition enforcement threshold
     * @dev the composition enforcement threshold is the total amount of deposits required for composition
     * targets to be enforced (if the threshold was 10000 and the targets for 2 lsds were 70% and 30%, up to
     * 7000 of the first lsd could be deposited even if there were no deposits of the second lsd but after 7000 is
     * reached, enough of the second lsd would have to be deposited to open up more room for the first lsd)
     * @param _compositionEnforcementThreshold threshold total deposit amount
     **/
    function setCompositionEnforcementThreshold(uint256 _compositionEnforcementThreshold) public onlyOwner {
        compositionEnforcementThreshold = _compositionEnforcementThreshold;
        emit SetCompositionEnforcementThreshold(_compositionEnforcementThreshold);
    }

    /**
     * @notice sets the withdrawal fee
     * @param _withdrawalFee fee in basis points
     **/
    function setWithdrawalFee(uint256 _withdrawalFee) public onlyOwner {
        require(_withdrawalFee <= 500, "Withdrawal fee must be <= 5%");
        withdrawalFee = _withdrawalFee;
        emit SetWithdrawalFee(_withdrawalFee);
    }

    /**
     * @notice adds a new fee
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function addFee(address _receiver, uint256 _feeBasisPoints) external onlyOwner {
        fees.push(Fee(_receiver, _feeBasisPoints));
        require(_totalFeesBasisPoints() <= 5000, "Total fees must be <= 50%");
        emit AddFee(_receiver, _feeBasisPoints);
    }

    /**
     * @notice updates an existing fee
     * @param _index index of fee
     * @param _receiver receiver of fee
     * @param _feeBasisPoints fee in basis points
     **/
    function updateFee(
        uint256 _index,
        address _receiver,
        uint256 _feeBasisPoints
    ) external onlyOwner {
        require(_index < fees.length, "Fee does not exist");

        if (_feeBasisPoints == 0) {
            fees[_index] = fees[fees.length - 1];
            fees.pop();
        } else {
            fees[_index].receiver = _receiver;
            fees[_index].basisPoints = _feeBasisPoints;
        }

        require(_totalFeesBasisPoints() <= 5000, "Total fees must be <= 50%");
        emit UpdateFee(_receiver, _feeBasisPoints);
    }

    /**
     * @notice pauses/unpauses the contract
     * @param _isPaused pause status of the contract
     **/
    function setPaused(bool _isPaused) external onlyOwner {
        require(_isPaused != isPaused, "This pause status is already set");
        isPaused = _isPaused;
    }

    /**
     * @notice returns the total underlying value of lsd tokens in the pool (excludes newly earned rewards)
     * @return the total underlying value
     */
    function _totalStaked() internal view override returns (uint256) {
        return totalStaked;
    }

    /**
     * @notice returns the total underlying value of lsd tokens in the pool (includes newly earned rewards)
     * @return the total underlying value
     */
    function _totalDeposits() internal view returns (uint256) {
        uint256 totalDepositAmounts;

        for (uint256 i = 0; i < lsdTokens.length; i++) {
            totalDepositAmounts += lsdAdapters[lsdTokens[i]].getTotalDeposits();
        }

        return totalDepositAmounts;
    }

    /**
     * @notice returns the sum of all fees
     * @return sum of fees in basis points
     **/
    function _totalFeesBasisPoints() internal view returns (uint256) {
        uint256 totalFees;
        for (uint i = 0; i < fees.length; i++) {
            totalFees += fees[i].basisPoints;
        }
        return totalFees;
    }

    /**
     * @notice returns the withdrawal fee to be paid on a withdrawal
     * @param _amount amount to withdraw
     * @return amount of tokens to be paid on withdrawal
     **/
    function _getWithdrawalFeeAmount(uint256 _amount) internal view returns (uint256) {
        return (_amount * withdrawalFee) / BASIS_POINTS_TOTAL;
    }
}