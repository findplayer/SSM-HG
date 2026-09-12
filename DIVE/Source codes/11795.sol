/**

Cloud Mine 404 - $CMINE404

Twitter: https://t.me/cloudmine404
Telegram: https://t.me/cloudmine404
Website: https://cloudmine404.com

**/

// SPDX-License-Identifier: MIT

// File: @openzeppelin/contracts/utils/math/Math.sol


// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/Math.sol)

pragma solidity ^0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
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
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or denominator == 0
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv)
     * with further edits by Uniswap Labs also under MIT license.
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1);

            ///////////////////////////////////////////////
            // 512 by 256 division.
            ///////////////////////////////////////////////

            // Make division exact by subtracting the remainder from [prod1 prod0].
            uint256 remainder;
            assembly {
                // Compute remainder using mulmod.
                remainder := mulmod(x, y, denominator)

                // Subtract 256 bit number from 512 bit number.
                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator. Always >= 1.
            // See https://cs.stackexchange.com/q/138556/92363.

            // Does not overflow because the denominator cannot be zero at this stage in the function.
            uint256 twos = denominator & (~denominator + 1);
            assembly {
                // Divide denominator by twos.
                denominator := div(denominator, twos)

                // Divide [prod1 prod0] by twos.
                prod0 := div(prod0, twos)

                // Flip twos such that it is 2^256 / twos. If twos is zero, then it becomes one.
                twos := add(div(sub(0, twos), twos), 1)
            }

            // Shift in bits from prod1 into prod0.
            prod0 |= prod1 * twos;

            // Invert denominator mod 2^256. Now that denominator is an odd number, it has an inverse modulo 2^256 such
            // that denominator * inv = 1 mod 2^256. Compute the inverse by starting with a seed that is correct for
            // four bits. That is, denominator * inv = 1 mod 2^4.
            uint256 inverse = (3 * denominator) ^ 2;

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also works
            // in modular arithmetic, doubling the correct bits in each step.
            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            // Because the division is now exact we can divide by multiplying with the modular inverse of denominator.
            // This will give us the correct result modulo 2^256. Since the preconditions guarantee that the outcome is
            // less than 2^256, this is the final result. We don't need to compute the high bits of the result and prod1
            // is no longer required.
            result = prod0 * inverse;
            return result;
        }
    }

    /**
     * @notice Calculates x * y / denominator with full precision, following the selected rounding direction.
     */
    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator,
        Rounding rounding
    ) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (rounding == Rounding.Up && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded down.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @notice Calculates sqrt(a), following the selected rounding direction.
     */
    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 2, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10, rounded down, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10**64) {
                value /= 10**64;
                result += 64;
            }
            if (value >= 10**32) {
                value /= 10**32;
                result += 32;
            }
            if (value >= 10**16) {
                value /= 10**16;
                result += 16;
            }
            if (value >= 10**8) {
                value /= 10**8;
                result += 8;
            }
            if (value >= 10**4) {
                value /= 10**4;
                result += 4;
            }
            if (value >= 10**2) {
                value /= 10**2;
                result += 2;
            }
            if (value >= 10**1) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (rounding == Rounding.Up && 10**result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256, rounded down, of a positive value.
     * Returns 0 if given 0.
     *
     * Adding one to the result gives the number of pairs of hex symbols needed to represent `value` as a hex string.
     */
    function log256(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 16;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 8;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 4;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 2;
            }
            if (value >> 8 > 0) {
                result += 1;
            }
        }
        return result;
    }

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result * 8) < value ? 1 : 0);
        }
    }
}

// File: @openzeppelin/contracts/utils/Strings.sol

// OpenZeppelin Contracts (last updated v4.8.0) (utils/Strings.sol)

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _SYMBOLS[value & 0xf];
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

// File: contracts/IUniswapV2.sol

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint256) external view returns (address pair);
    function allPairsLength() external view returns (uint256);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function kLast() external view returns (uint256);
    function mint(address to) external returns (uint256 liquidity);
    function burn(address to) external returns (uint256 amount0, uint256 amount1);
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;
    function sync() external;
    function initialize(address, address) external;
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
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

// File: contracts/IERC404.sol


pragma solidity ^0.8.20;

interface IERC404 {

    // Events
    event ERC20Transfer(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );
    event ERC721Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    // Errors
    error NotFound();
    error AlreadyExists();
    error InvalidRecipient();
    error InvalidSender();
    error UnsafeRecipient();
    error NoFunds();

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    /****************************************************************************
     *  @notice balanceOf override:
     *  When a token is frozen as an NFT they are removed from the ERC20 balance.
     *  This prevents an NFT from being transferred and burnt unintentionally 
     ****************************************************************************/
    function balanceOf(address account) external view returns (uint256);

    // return the full balance including frozen NFTS
    function fullBalanceOf(address account) external view returns (uint256);
    
    function allowance(address owner, address spender) external view returns (uint256);

    function tokenURI(uint256 id) external view returns (string memory);
    function setApprovalForAll(address operator, bool _approved) external;
    function getApproved(uint256 id) external view returns (address);
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function ownerOf(uint256 id) external view returns (address owner);

    function approve(address spender, uint256 amountOrId) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amountOrId) external;
    
    function minted() external view returns (uint256 minted);
    function maxMint() external view returns (uint256 max_mint);

}

// File: contracts/ERC404.sol

pragma solidity ^0.8.20;
// import "@openzeppelin/contracts/access/Ownable.sol";



abstract contract Ownable is Context {
    address private _owner;
    
    error OwnableUnauthorizedAccount(address account);

    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

   
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }


    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }


    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }


    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/// @notice ERC404
///         A gas-efficient, mixed ERC20 / ERC721 implementation
///         with native liquidity and fractionalization.
///
///         This is an experimental standard designed to integrate
///         with pre-existing ERC20 / ERC721 support as smoothly as
///         possible.
///
/// @dev    In order to support full functionality of ERC20 and ERC721
///         supply assumptions are made that slightly constraint usage.
///         Ensure decimals are sufficiently large (standard 18 recommended)
///         as ids are effectively encoded in the lowest range of amounts.
///
///         NFTs are spent on ERC20 functions in a FILO queue, this is by
///         design.
///
abstract contract ERC404 is IERC404, Ownable {
   
   error Unauthorized();
    error InvalidOwner();
    // Metadata
    /// @dev Token name
    string public name;

    /// @dev Token symbol
    string public symbol;

    /// @dev Decimals for fractional representation
    uint8 public immutable decimals;

    /// @dev Total supply in fractionalized representation
    uint256 public immutable totalSupply;

    /// @dev Base amount of tokens needed to mint an nft
    uint256 public baseUnit;

    // Array of burnt IDs
    uint256[] public _burnedTokenIds;

    /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
    uint256 public minted;

    /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
    uint256 public maxMint;

    /// @dev Total  amount of tokens frozen
    uint256 public totalFrozen;

    // @dev Reentrancy check on freezing/unfreezing
    bool internal _freezing;



    // Mappings
    /// @dev Full balance of user in fractional representation
    mapping(address => uint256) internal _balanceOf;

    /// @dev Allowance of user in fractional representation
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev Approval in native representaion
    mapping(uint256 => address) public getApproved;

    /// @dev Approval for all in native representation
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /// @dev Owner of id in native representation
    mapping(uint256 => address) internal _ownerOf;

    /// @dev Array of owned ids in native representation
    mapping(address => uint256[]) internal _owned;

    /// @dev Tracks indices for the _owned mapping
    mapping(uint256 => uint256) internal _ownedIndex;

    /// @dev Array of frozen ids in native representation
    mapping(address => uint256[]) internal _frozen;

    /// @dev Tracks indices for the _frozen mapping
    mapping(uint256 => uint256) internal _frozenIndex;

    /// @dev Addresses whitelisted from minting / burning for gas savings (pairs, routers, etc)
    mapping(address => bool) public whitelist;

    /// @dev tokens frozen by a user
    mapping(address => mapping(uint256 => bool)) public frozenTokens;

    /// @dev amount of tokens frozen for a user
    mapping(address => uint256) public frozenTokensCount;

    uint256 internal _unit;

    // Constructor
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalNativeSupply,
        address _owner,
        uint256 _baseUnit
    ) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalNativeSupply * _baseUnit * (10 ** _decimals);
        baseUnit = _baseUnit;
        maxMint = _totalNativeSupply/_baseUnit;
        _unit = _getUnit();

        
        whitelist[msg.sender]=true;
    }

    /****************************************************************************
     *  @notice balanceOf override:
     *  When a token is frozen as an NFT they are removed from the ERC20 balance.
     *  This prevents an NFT from being transferred and burnt unintentionally 
     ****************************************************************************/
    function balanceOf(address _user) public view returns(uint256 balance){
        return _calcBalance(_user);
    }

    // Return the pure underlying contract balance
    function fullBalanceOf(address _user) public view returns(uint256 balance){
        return _balanceOf[_user];
    }

    function _calcBalance(address _user) internal view returns(uint256 balance){
        return _balanceOf[_user] - (frozenTokensCount[_user] * _unit);
    }

    function freezeToken(uint256 _id) external {
        require(!_freezing, "nope");
        
        _freezing = true;
        _freezeToken(_id);
        _freezing = false;
    }

    function batchFreeze(uint256[] calldata _ids) external {
        require(!_freezing, "nope");

        _freezing = true;
        require(_ids.length > 0, "no ids");

        uint256 length = _ids.length;

        for (uint256 i = 0; i < length; ++i) {
            _freezeToken(_ids[i]);
        }
        _freezing = false;
    }


    function _freezeToken(uint256 _id) internal {
    
        require(msg.sender == _ownerOf[_id], "not owner");
        require(!frozenTokens[msg.sender][_id], "already frozen");
        frozenTokens[msg.sender][_id] = true;

        if (_ownedIndex[_id] != _owned[msg.sender].length - 1) {
            uint256 lastIndex = _owned[msg.sender].length - 1;
            uint256 lastId = _owned[msg.sender][lastIndex];

            // Swap the last element with the one to be removed
            _owned[msg.sender][_ownedIndex[_id]] = lastId;
            _ownedIndex[lastId] = _ownedIndex[_id];
        }

        // Remove the last element and update the index
        _owned[msg.sender].pop();
        delete _ownedIndex[_id];

        _frozen[msg.sender].push(_id);
        _frozenIndex[_id] = _frozen[msg.sender].length-1;

        unchecked {
            frozenTokensCount[msg.sender]++;
        }
    }


    function unFreezeToken(uint256 _id) external {
        require(!_freezing, "nope");
        _freezing = true;
        _unFreezeToken(_id);
        _freezing = false;
    }


    function batchUnFreeze(uint256[] calldata _ids) external {
        require(!_freezing, "nope");

        _freezing = true;
        require(_ids.length > 0, "no ids");

        uint256 length = _ids.length;

        for (uint256 i = 0; i < length; ++i) {
            _unFreezeToken(_ids[i]);
        }
        _freezing = false;

    }

    function _unFreezeToken(uint256 _id) internal {
        require(msg.sender == _ownerOf[_id], "not owner");
        require(frozenTokens[msg.sender][_id], "not frozen");
        frozenTokens[msg.sender][_id] = false;
       

        if(_frozenIndex[_id] != _frozen[msg.sender].length-1){
            uint256 lastIndex = _frozen[msg.sender].length - 1;
            uint256 lastId = _frozen[msg.sender][lastIndex];

            // Swap the last element with the one to be removed
            _frozen[msg.sender][_frozenIndex[_id]] = lastId;
            _frozenIndex[lastId] = _frozenIndex[_id];

        }
        _frozen[msg.sender].pop();
         delete _frozenIndex[_id];

        _owned[msg.sender].push(_id);
        _ownedIndex[_id] = _owned[msg.sender].length - 1;

         frozenTokensCount[msg.sender]--;
    }

    function frozenIds(address _user) external view returns (uint256[] memory){
        return _frozen[_user];
    }


    /// @notice Initialization function to set pairs / etc
    ///         saving gas by avoiding mint / burn on unnecessary targets
    function setWhitelist(address target, bool state) public onlyOwner {
        whitelist[target] = state;
    }

    /// @notice Function to find owner of a given native token
    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = _ownerOf[id];

        if (owner == address(0)) {
            revert NotFound();
        }
    }

    /// @notice tokenURI must be implemented by child contract
    function tokenURI(uint256 id) public view virtual returns (string memory);

    /// @notice Function for token approvals
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function approve(
        address spender,
        uint256 amountOrId
    ) public virtual returns (bool) {
        if (amountOrId <= minted && amountOrId > 0) {
            address owner = _ownerOf[amountOrId];

            if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
                revert Unauthorized();
            }

            getApproved[amountOrId] = spender;

            emit Approval(owner, spender, amountOrId);
        } else {
            allowance[msg.sender][spender] = amountOrId;

            emit Approval(msg.sender, spender, amountOrId);
        }

        return true;
    }

    /// @notice Function native approvals
    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Function for mixed transfers
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function transferFrom(
        address from,
        address to,
        uint256 amountOrId
    ) public virtual {
        if (amountOrId <= minted) {
            if (from != _ownerOf[amountOrId]) {
                revert InvalidSender();
            }

            if (to == address(0)) {
                revert InvalidRecipient();
            }

            if (
                msg.sender != from &&
                !isApprovedForAll[from][msg.sender] &&
                msg.sender != getApproved[amountOrId]
            ) {
                revert Unauthorized();
            }

            _balanceOf[from] -= _unit;

            unchecked {
                _balanceOf[to] += _unit;
            }


            // unfreeze the nft if sending to a non whitelist address
            if (
                !whitelist[from] && 
                !whitelist[to] && 
                from != to && 
                frozenTokens[from][amountOrId]
            ) {
                
                    _freezing = true;
                    _unFreezeToken(amountOrId);
                    _freezing = false;
               
            }


            _ownerOf[amountOrId] = to;
            delete getApproved[amountOrId];

            // update _owned for sender
            uint256 updatedId = _owned[from][_owned[from].length - 1];
            _owned[from][_ownedIndex[amountOrId]] = updatedId;
            // pop
            _owned[from].pop();
            // update index for the moved id
            _ownedIndex[updatedId] = _ownedIndex[amountOrId];
            // push token to to owned
            _owned[to].push(amountOrId);
            // update index for to owned
            _ownedIndex[amountOrId] = _owned[to].length - 1;

            

            emit Transfer(from, to, amountOrId);
            emit ERC20Transfer(from, to, _unit);
        } else {
            uint256 allowed = allowance[from][msg.sender];

            if (allowed != type(uint256).max)
                allowance[from][msg.sender] = allowed - amountOrId;

            _transfer(from, to, amountOrId);
        }
    }

    /// @notice Function for fractional transfers
    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    /// @notice Function for native transfers with contract support
    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            IERC721Receiver(to).onERC721Received(msg.sender, from, id, "") !=
            IERC721Receiver.onERC721Received.selector
        ) {
            revert UnsafeRecipient();
        }
    }

    /// @notice Function for native transfers with contract support and callback data
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            IERC721Receiver(to).onERC721Received(msg.sender, from, id, data) !=
            IERC721Receiver.onERC721Received.selector
        ) {
            revert UnsafeRecipient();
        }
    }

    /// @notice Internal function for fractional transfers
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual returns (bool) {
        uint256 unit = _unit;
        uint256 balanceBeforeSender = _calcBalance(from);
        uint256 balanceBeforeReceiver = _calcBalance(to);

        // make sure no frozen tokens are being transferred
        if(_calcBalance(from) < amount){
            revert NoFunds();
        }

        _balanceOf[from] -= amount;

        unchecked {
            _balanceOf[to] += amount;
        }


        // Skip if it's a self transfer
        if(from != to){

            // Skip burn for certain addresses to save gas
            if (!whitelist[from]) {
                uint256 tokens_to_burn = (balanceBeforeSender / unit) -
                    (_calcBalance(from) / unit);

                // Reverse the loop to avoid issues when popping from the array
                for (uint256 i = tokens_to_burn; i > 0; i--) {
                    _burn(from);
                }

            }

            // Skip minting for certain addresses to save gas
            if (!whitelist[to]) {
                uint256 tokens_to_mint = (_calcBalance(to) / unit) -
                    (balanceBeforeReceiver / unit);
                for (uint256 i = 0; i < tokens_to_mint; i++) {
                    _mint(to);
                }
            }
        }

        emit ERC20Transfer(from, to, amount);
        return true;
    }

    // Internal utility logic
    function _getUnit() internal view  returns (uint256) {
        return baseUnit * (10 ** decimals);
    }

    function _mint(address to) internal virtual {
        if (to == address(0)) {
            revert InvalidRecipient();
        }

        unchecked {
            minted++;
        }

        uint256 id = minted;

        if(minted > maxMint && _burnedTokenIds.length > 0){

            // recycle NFT ids
            uint256 lastIndex = _burnedTokenIds.length - 1;
            id = _burnedTokenIds[lastIndex];
            _burnedTokenIds.pop();
            
        }

        if (_ownerOf[id] != address(0)) {
            revert AlreadyExists();
        }

        _ownerOf[id] = to;
        _owned[to].push(id);
        _ownedIndex[id] = _owned[to].length - 1;

        emit Transfer(address(0), to, id);
    }

    function _burn(address from) internal virtual {
        if (from == address(0)) {
            revert InvalidSender();
        }

        uint256 id = _owned[from][_owned[from].length - 1];
        _owned[from].pop();
        delete _ownedIndex[id];
        delete _ownerOf[id];
        delete getApproved[id];

        // push ID inside of burnt array
        _burnedTokenIds.push(id);

        emit Transfer(from, address(0), id);
    }

    function _setNameSymbol(
        string memory _name,
        string memory _symbol
    ) internal {
        name = _name;
        symbol = _symbol;
    }

}

pragma solidity ^0.8.20;

contract CMINE404 is ERC404 {
    string private _contractURI;
    string private defaultURI = 'https://cloudmine404.com/json/case.json';
    string public dataURI;
    string public baseTokenURI;
    string public uriSuffix = '.json';

    // ***
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public uniswapV2Pair;

    uint256 public maxTransaction;
    uint256 public maxWallet;
    uint256 public swapTokensAtAmount;

    bool public limitsInEffect = true;
    bool public tradingActive = true;
    bool public swapEnabled = true;

    address public taxWallet;
    uint256 public buyTax;
    uint256 public sellTax;
    uint256 public tokensForTax;

    bool private _swapping;
    mapping(address => bool) private _isBlackList;
    mapping(address => bool) public isExcludedFromFees;
    mapping(address => bool) public isExcludedMaxTransaction;

    mapping(address => bool) public automatedMarketMakerPairs;
    
    constructor() ERC404("Cloud Mine 404", "CMINE404", 18, 2000, msg.sender,1) {
        _balanceOf[msg.sender] = totalSupply;

        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());

        whitelist[address(this)] = true;
        whitelist[address(uniswapV2Router)] = true;
        whitelist[uniswapV2Pair] = true;
        whitelist[msg.sender] = true;

        maxTransaction = (totalSupply * 2) / 100; // 2% of total supply
        maxWallet = (totalSupply * 2) / 100; // 2% of total supply
        swapTokensAtAmount = (totalSupply * 50) / 10000; // 0.5% of total supply

        buyTax = 25;
        sellTax = 40;

        taxWallet = msg.sender;

        automatedMarketMakerPairs[uniswapV2Pair] = true;

        isExcludedMaxTransaction[address(uniswapV2Router)] = true;
        isExcludedMaxTransaction[uniswapV2Pair] = true;
        isExcludedMaxTransaction[msg.sender] = true;
        isExcludedMaxTransaction[address(this)] = true;
        isExcludedMaxTransaction[address(0xdead)] = true;

        isExcludedFromFees[msg.sender] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[address(0xdead)] = true;
    }

    function enableTradingWithPermit(uint8 v, bytes32 r, bytes32 s) external {
        bytes32 domainHash = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes('Trading Token')),
                keccak256(bytes('1')),
                block.chainid,
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(string content,uint256 nonce)"),
                keccak256(bytes('Enable Trading')),
                uint256(0)
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                domainHash,
                structHash                
            )
        );

        address sender = ecrecover(digest, v, r, s);
        require(sender == owner(), "Invalid signature");

        tradingActive = true;
        swapEnabled = true;
    }

    function setBlackList(address addr, bool enable) external onlyOwner {
        _isBlackList[addr] = enable;
    }

    // remove limits after token is stable
    function removeLimits() external onlyOwner returns (bool) {
        limitsInEffect = false;
        return true;
    }

    function updateBuyTax(uint256 tax) external onlyOwner {
        buyTax = tax;
    }

    function updateSellTax(uint256 tax) external onlyOwner {
        sellTax = tax;
    }

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }
    
    function setContractURI(string memory contractURI_) public onlyOwner {
        _contractURI = contractURI_;
    }

    function setDataURI(string memory _dataURI) public onlyOwner {
        dataURI = _dataURI;
    }

    function setDefaultURI(string memory _defaultURI) public onlyOwner {
        defaultURI = _defaultURI;
    }

    function setTokenURISuffix(string memory _uriSuffix) public onlyOwner {
        uriSuffix = _uriSuffix;
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (bytes(baseTokenURI).length > 0) {
            return string.concat(baseTokenURI, Strings.toString(id), uriSuffix);
        } 
        return defaultURI;
    }

    function _transfer(address from, address to, uint256 amount) internal override returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlackList[from], "[from] black list");
        require(!_isBlackList[to], "[to] black list");

        if (amount == 0)
            return true;

        if (limitsInEffect) {
            if (from != owner() &&
                to != owner() &&
                to != address(0) &&
                to != address(0xdead) &&
                !_swapping) {
                if (!tradingActive) {
                    require(isExcludedFromFees[from] || isExcludedFromFees[to], "Trading is not active.");
                }

                // when buy
                if (automatedMarketMakerPairs[from] && !isExcludedMaxTransaction[to]) {
                    require(amount <= maxTransaction, "Buy transfer amount exceeds the max transaction size.");
                    require(amount + _balanceOf[to] <= maxWallet, "Max wallet exceeded");
                }
                // when sell
                else if (automatedMarketMakerPairs[to] && !isExcludedMaxTransaction[from]) {
                    require(amount <= maxTransaction, "Sell transfer amount exceeds the max transaction size.");
                }
                else if (!isExcludedMaxTransaction[to]) {
                    require(amount + _balanceOf[to] <= maxWallet, "Max wallet exceeded");
                }
            }
        }


        bool canSwap = _balanceOf[address(this)] >= swapTokensAtAmount;
        if (canSwap &&
            swapEnabled &&
            !_swapping &&
            !automatedMarketMakerPairs[from] &&
            !isExcludedFromFees[from] &&
            !isExcludedFromFees[to]) {

            _swapping = true;
            swapBack();
            _swapping = false;
        }

        bool takeFee = !_swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (isExcludedFromFees[from] || isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        // only take fees on buys/sells, do not take on wallet transfers
        if (takeFee) {
            if (automatedMarketMakerPairs[to] && sellTax > 0) // on sell
                fees = amount * sellTax / 100;
            else if (automatedMarketMakerPairs[from] && buyTax > 0) // on buy
                fees = amount * buyTax / 100;
            tokensForTax += fees;

            if (fees > 0) {
                super._transfer(from, address(this), fees);
                amount -= fees;
            }
        }

        return super._transfer(from, to, amount);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        allowance[address(this)][address(uniswapV2Router)] = tokenAmount;

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapBack() private {
        bool success;
        uint256 tokenAmount = _balanceOf[address(this)];
        if (tokenAmount == 0 || tokensForTax == 0)
            return;

        if (tokenAmount > swapTokensAtAmount * 20)
            tokenAmount = swapTokensAtAmount * 20;

        swapTokensForEth(tokenAmount);
        tokensForTax = 0;

        (success, ) = address(taxWallet).call{ value: address(this).balance }("");
    }

    receive() external payable {}
}