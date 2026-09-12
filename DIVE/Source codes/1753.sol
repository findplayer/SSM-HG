// Sources flattened with hardhat v2.19.4 https://hardhat.org

// SPDX-License-Identifier: GPL-3.0 AND MIT

// File @openzeppelin/contracts/utils/Context.sol@v5.0.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.1) (utils/Context.sol)

pragma solidity ^0.8.20;

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

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}


// File @openzeppelin/contracts/access/Ownable.sol@v5.0.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity ^0.8.20;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
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
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
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


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v5.0.1

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
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
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}


// File contracts/PlanetPreOrderV2.sol

// Original license: SPDX_License_Identifier: GPL-3.0

pragma solidity >=0.8.20;


contract PlanetPreOrderV2 is Ownable {
    fallback() external payable{}
    receive() external payable{}

    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant PLANET = 0x2aD9adDD0d97EC3cDBA27F92bF6077893b76Ab0b;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public treasury = 0x205431803FC9e4d6F84F3EaFd140D0800d00996B;
    address public signer = 0x08D36e210aa66e5cec84d8A6543C9f0805c5C5d7;

    uint256 public reservations = 0;

    mapping(address => uint256) public reserved;
    mapping(address => bool) public currencies;

    event Reserve(address indexed user, address indexed currency, uint256 price);

    constructor() Ownable(msg.sender) {
        currencies[USDT] = true;
        currencies[USDC] = true;
        currencies[WETH] = true;
        currencies[PLANET] = true;
    }

    function formMessage(address _user, address _currency, uint256 _unitPrice, uint256 _deadline) external view returns (bytes32) {
        return keccak256(abi.encodePacked(address(this), _user, _currency, _unitPrice, _deadline));
    }

    function isValidSignature(address _user, address _currency, uint256 _unitPrice, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) view public returns (bool) {
        bytes memory packedHash = abi.encodePacked(address(this), _user, _currency, _unitPrice, _deadline);
        bytes32 hash = keccak256(packedHash);
        bytes memory packedString = abi.encodePacked("\x19Ethereum Signed Message:\n32", hash);
        return ecrecover(keccak256(packedString), _v, _r, _s) == signer;
    }

    function reserve(address _currency, uint256 _price, uint256 _deadline, uint8 _v, bytes32 _r, bytes32 _s) external payable {
        require(currencies[_currency], "Invalid currency");
        require(isValidSignature(msg.sender, _currency, _price, _deadline, _v, _r, _s), "Invalid permit");

        if (_currency == WETH && msg.value > 0) {
            // Minting with WETH
            // Amount of WETH sent must be correct
            require(msg.value >= _price, "Transaction underpriced");

            // Pay to treasury
            payable(treasury).transfer(msg.value);

        } else {
            // Current currency balance of contract
            uint256 currentBalance = IERC20(_currency).balanceOf(address(this));

            // Transfer the tokens to the contract
            IERC20(_currency).transferFrom(msg.sender, address(this), _price);

            // Check if the tokens were transferred
            uint256 newBalance = IERC20(_currency).balanceOf(address(this));
            require((newBalance - currentBalance) >= _price, "Cannot transfer enough tokens");

            IERC20(_currency).transfer(treasury, newBalance);
        }

        emit Reserve(msg.sender, _currency, _price);
        reserved[msg.sender]++;
        reservations++;
    }

    function setTreasury(address _treasury) external onlyOwner {
        treasury = _treasury;
    }

    function setCurrency(address _currency, bool _enabled) external onlyOwner {
        currencies[_currency] = _enabled;
    }

    function setSigner(address _signer) external onlyOwner {
        signer = _signer;
    }

    function addV1Reservations(address[] calldata _user, address[] calldata _currency, uint256[] calldata _price) external onlyOwner {
        require(_user.length == _currency.length && _currency.length == _price.length, "Invalid input");
        for (uint256 i = 0; i < _user.length; i++) {
            reserved[_user[i]]++;
            reservations++;
            emit Reserve(_user[i], _currency[i], _price[i]);
        }
    }

    function rescueTokens(address _token) external onlyOwner {
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    function rescueETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}