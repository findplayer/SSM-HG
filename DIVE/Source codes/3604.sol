/// SPDX-License-Identifier: MIT
// File: @openzeppelin/contracts/utils/math/SignedMath.sol


// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/SignedMath.sol)

pragma solidity ^0.8.20;

/**
 * @dev Standard signed math utilities missing in the Solidity language.
 */
library SignedMath {
    /**
     * @dev Returns the largest of two signed numbers.
     */
    function max(int256 a, int256 b) internal pure returns (int256) {
        return a > b ? a : b;
    }

    /**
     * @dev Returns the smallest of two signed numbers.
     */
    function min(int256 a, int256 b) internal pure returns (int256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two signed numbers without overflow.
     * The result is rounded towards zero.
     */
    function average(int256 a, int256 b) internal pure returns (int256) {
        // Formula from the book "Hacker's Delight"
        int256 x = (a & b) + ((a ^ b) >> 1);
        return x + (int256(uint256(x) >> 255) & (a ^ b));
    }

    /**
     * @dev Returns the absolute unsigned value of a signed value.
     */
    function abs(int256 n) internal pure returns (uint256) {
        unchecked {
            // must be unchecked in order to support `n = type(int256).min`
            return uint256(n >= 0 ? n : -n);
        }
    }
}

// File: @openzeppelin/contracts/utils/math/Math.sol


// OpenZeppelin Contracts (last updated v5.0.0) (utils/math/Math.sol)

pragma solidity ^0.8.20;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Muldiv operation overflow.
     */
    error MathOverflowedMulDiv();

    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }

    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
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
     * This differs from standard division with `/` in that it rounds towards infinity instead
     * of rounding towards zero.
     */
    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        if (b == 0) {
            // Guarantee the same behavior as in a regular Solidity division.
            return a / b;
        }

        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    /**
     * @notice Calculates floor(x * y / denominator) with full precision. Throws if result overflows a uint256 or
     * denominator == 0.
     * @dev Original credit to Remco Bloemen under MIT license (https://xn--2-umb.com/21/muldiv) with further edits by
     * Uniswap Labs also under MIT license.
     */
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
        unchecked {
            // 512-bit multiply [prod1 prod0] = x * y. Compute the product mod 2^256 and mod 2^256 - 1, then use
            // use the Chinese Remainder Theorem to reconstruct the 512 bit result. The result is stored in two 256
            // variables such that product = prod1 * 2^256 + prod0.
            uint256 prod0 = x * y; // Least significant 256 bits of the product
            uint256 prod1; // Most significant 256 bits of the product
            assembly {
                let mm := mulmod(x, y, not(0))
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }

            // Handle non-overflow cases, 256 by 256 division.
            if (prod1 == 0) {
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            if (denominator <= prod1) {
                revert MathOverflowedMulDiv();
            }

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

            // Factor powers of two out of denominator and compute largest power of two divisor of denominator.
            // Always >= 1. See https://cs.stackexchange.com/q/138556/92363.

            uint256 twos = denominator & (0 - denominator);
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

            // Use the Newton-Raphson iteration to improve the precision. Thanks to Hensel's lifting lemma, this also
            // works in modular arithmetic, doubling the correct bits in each step.
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
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
        uint256 result = mulDiv(x, y, denominator);
        if (unsignedRoundsUp(rounding) && mulmod(x, y, denominator) > 0) {
            result += 1;
        }
        return result;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
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
            return result + (unsignedRoundsUp(rounding) && result * result < a ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
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
            return result + (unsignedRoundsUp(rounding) && 1 << result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
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
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Return the log in base 256 of a positive value rounded towards zero.
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
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (unsignedRoundsUp(rounding) && 1 << (result << 3) < value ? 1 : 0);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}

// File: @openzeppelin/contracts/utils/Strings.sol


// OpenZeppelin Contracts (last updated v5.0.0) (utils/Strings.sol)

pragma solidity ^0.8.20;



/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;

    /**
     * @dev The `value` string doesn't fit in the specified `length`.
     */
    error StringsInsufficientHexLength(uint256 value, uint256 length);

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
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    /**
     * @dev Converts a `int256` to its ASCII `string` decimal representation.
     */
    function toStringSigned(int256 value) internal pure returns (string memory) {
        return string.concat(value < 0 ? "-" : "", toString(SignedMath.abs(value)));
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
        uint256 localValue = value;
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = HEX_DIGITS[localValue & 0xf];
            localValue >>= 4;
        }
        if (localValue != 0) {
            revert StringsInsufficientHexLength(value, length);
        }
        return string(buffer);
    }

    /**
     * @dev Converts an `address` with fixed length of 20 bytes to its not checksummed ASCII `string` hexadecimal
     * representation.
     */
    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), ADDRESS_LENGTH);
    }

    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return bytes(a).length == bytes(b).length && keccak256(bytes(a)) == keccak256(bytes(b));
    }
}

// File: @openzeppelin/contracts/token/ERC721/IERC721Receiver.sol


// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC721/IERC721Receiver.sol)

pragma solidity ^0.8.20;

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
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be
     * reverted.
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

// File: @openzeppelin/contracts/interfaces/IERC721Receiver.sol


// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC721Receiver.sol)

pragma solidity ^0.8.20;


// File: @openzeppelin/contracts/utils/Context.sol


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

// File: @openzeppelin/contracts/access/Ownable.sol


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

// File: contracts/ERC404C.sol
pragma solidity ^0.8.21;

/**
 * @title ERC404C: Advanced ERC404 Standard for Gas-Efficient Hybrid Tokens
 * @dev Extends {Ownable} from OpenZeppelin for ownership management.
 * 
 * ERC404C enhances the ERC404 framework by introducing optimizations and features that 
 * aim to improve gas efficiency and expand functionality. It retains the innovative 
 * combination of ERC20 and ERC721 token features, supporting liquidity, fractional 
 * ownership, and seamless interoperability within the Ethereum ecosystem.
 * 
 * Core Features Inherited from ERC404:
 * - Hybrid Functionality: Continues the integration of ERC20 fractionalization with ERC721 
 *   uniqueness, facilitating a versatile environment for tokens with dual characteristics.
 * - FILO Queue for NFT Spending: Preserves the First-In-Last-Out (FILO) mechanism for managing 
 *   NFT usage in ERC20 transactions, ensuring a consistent and user-friendly approach.
 * 
 * Unique Enhancements in ERC404C:
 * - Gas Efficiency: Introduces advanced storage optimization and token ID recycling techniques
 *   to significantly reduce gas consumption beyond the original ERC404 standard. By refining
 *   the storage structure and limiting the need for new token ID generation, ERC404C sets a 
 *   new benchmark for contract efficiency.
 * - Customizable Burn Priority: Implements the `setLastOwnedTokenId(tokenId)` function, granting 
 *   users the ability to determine the priority of NFTs to be burned within the FILO queue, thus 
 *   offering strategic control over their digital assets.
 * - ERC20-Only Interaction Mode: Adds the `setWhitelist()` functionality, allowing users 
 *   to opt for an ERC20-exclusive interaction mode. This irreversible setting optimizes gas fees 
 *   for ERC20 transactions and prevents the wallet from engaging in ERC721 token receptions, 
 *   emphasizing a streamlined focus on ERC20 token transactions.
 * 
 * Implementation Considerations:
 * - Token ID Recycling: Emphasizes the efficient reuse of token IDs within the 2^32 collection size 
 *   limit to maintain high levels of gas efficiency.
 * - Storage Optimization: Encodes token details into a single 256-bit word, drastically cutting 
 *   storage costs and improving contract performance.
 * - Decimal Precision: Maintains the 18 decimal precision for ERC20 fractions, enabling precise 
 *   and flexible token interactions.
 * 
 * Note: ERC404C represents a significant advancement of the ERC404 standard, incorporating 
 * experimental features to enhance efficiency and utility. Developers and users are encouraged 
 * to conduct extensive testing in various settings to fully evaluate its capabilities and 
 * compatibility with diverse applications.
 */



 abstract contract ERC404C is Ownable {

    // Compiler will pack this into a single 256bit word.
    struct TokenDetail {
        // The address of the owner.
        address owner;              
        // Mapping from TokenID to index in _allToken list
        uint32  allTokensIndex;     
        // Mapping from TokenID to index in _ownedTokens list
        uint32  ownedTokensIndex;   
        // Reserved for other used;
        bytes4  aux;    
    }

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
    error Unauthorized();

    // Metadata
    /// @dev Token name
    string public name;

    /// @dev Token symbol
    string public symbol;

    /// @dev Decimals for fractional representation
    uint8 public immutable decimals;

    /// @dev Decimals for conversion between fractional representation and native represetation
    uint8 public immutable nativeDecimals;

    /// @dev Total supply in fractionalized representation
    uint256 public immutable totalSupply;

    /// @dev Total native supply 
    uint256 public immutable totalNativeSupply;

    /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
    uint256 public minted;

    // Mappings
    // @dev Mapping from token ID to token Detail 
    mapping(uint256 => TokenDetail) private _tokenDetail;

    // @dev Mapping from owner to list of owned token IDs
    mapping(address => uint32[]) private _ownedTokens;

    /// @dev Balance of user in fractional representation
    mapping(address => uint256) public balanceOf;

    /// @dev Allowance of user in fractional representation
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev Approval in native representaion
    mapping(uint256 => address) public getApproved;

    /// @dev Approval for all in native representation
    mapping(address => mapping(address => bool)) public isApprovedForAll;

     /// @dev Addresses whitelisted from minting / burning for gas savings (pairs, routers, etc)
    mapping(address => bool) public whitelist;
   
    // @dev Array with all token ids, used for enumeration
    uint32[] private _allTokens; 
    uint32[] private _burntTokens;

    // Constructor
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint8 _nativeDecimals,
        uint256 _totalNativeSupply,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        nativeDecimals = _nativeDecimals;
        totalNativeSupply = _totalNativeSupply;
        totalSupply = _totalNativeSupply * (10 ** nativeDecimals);
        setWhitelist(_owner,true);
        setWhitelist(address(0), true);
    }

    function _setWhiteList(address target, bool state) internal {
        if (!whitelist[target] && state) {
            whitelist[target] = true;
            uint256 tokens_to_burn = balanceOf[target] / _getUnit();
            for (uint i = 0; i < tokens_to_burn; i++) {
                _burn(target);
            }
        } else if (whitelist[target] && !state) {
            whitelist[target] = false;
            uint256 tokens_to_mint = balanceOf[target] / _getUnit();
            for (uint i = 0; i < tokens_to_mint; i++) {
                _mint(target);
            }
        }    
    }

    /// @notice Initialization function to set pairs / etc
    ///         saving gas by avoiding mint / burn on unnecessary targets
    function setWhitelist(address target, bool state) public onlyOwner {
        _setWhiteList(target, state);
    }

    /// @notice Allows a user to select mode for the wallet.
    uint256 immutable whitelist_reset_cooldown = 10000; 
    mapping (address => uint256)  private _last_whitelist_reset_block; 
    function setWhitelist(bool state) public {   	
        if (!state && whitelist[msg.sender]) {
            uint256 time_from_last_reset = block.number - _last_whitelist_reset_block[msg.sender];
            require (time_from_last_reset > whitelist_reset_cooldown, "Whitelsit cool down period is not ended");
            _last_whitelist_reset_block[msg.sender] = block.number;
        }
        _setWhiteList(msg.sender, state);
    }

    /// @notice Function to find owner of a given native token
    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = _tokenDetail[id].owner;
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
            address owner = _tokenDetail[amountOrId].owner; 

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
        if (amountOrId <= totalNativeSupply) {

            // This is a ERC721 Transfer
            if (from != _tokenDetail[amountOrId].owner) {
                revert InvalidSender();
            }

            if (to == address(0) || whitelist[to]) { 
                revert InvalidRecipient();
            }

            if (
                msg.sender != from &&
                !isApprovedForAll[from][msg.sender] &&
                msg.sender != getApproved[amountOrId]
            ) {
                revert Unauthorized();
            }

            balanceOf[from] -= _getUnit();

            unchecked {
                balanceOf[to] += _getUnit();
            }

            delete getApproved[amountOrId];

            _tokenDetail[amountOrId].owner = to;
        
            // _removeTokenFromOwnerEnumeration(from, tokenId);        
            uint32[] storage fromTokenList = _ownedTokens[from];
            TokenDetail storage tokenDetail = _tokenDetail[amountOrId];
            uint32 tokenIndex = tokenDetail.ownedTokensIndex;
            uint32 lastToken = fromTokenList[fromTokenList.length - 1];
            fromTokenList[tokenIndex] = lastToken;
            _tokenDetail[lastToken].ownedTokensIndex = tokenIndex;
            fromTokenList.pop();

            // _addTokenToOwnerEnumeration(to, tokenId);
            uint32[] storage toTokenList = _ownedTokens[to];
            tokenDetail.ownedTokensIndex = uint32(toTokenList.length);
            toTokenList.push(uint32(amountOrId));
    
            emit Transfer(from, to, amountOrId);
            emit ERC20Transfer(from, to, _getUnit());
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
    ) internal returns (bool) {
        uint256 unit = _getUnit();
        uint256 balanceBeforeSender = balanceOf[from];
        uint256 balanceBeforeReceiver = balanceOf[to];

        _beforeTransfer(from, to, amount);

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        // Skip burn for certain addresses to save gas
        if (!whitelist[from]) {
            uint256 tokens_to_burn = (balanceBeforeSender / unit) - (balanceOf[from] / unit);
            for (uint256 i = 0; i < tokens_to_burn; i++) {
                _burn(from);
            }
        }

        // Skip minting for certain addresses to save gas
        if (!whitelist[to]) {
            uint256 tokens_to_mint = (balanceOf[to] / unit) - (balanceBeforeReceiver / unit);
            for (uint256 i = 0; i < tokens_to_mint; i++) {
                _mint(to);
            }
        }

        emit ERC20Transfer(from, to, amount);

        _afterTransfer(from, to, amount);

        return true;
    }

    // Internal utility logic
    function _getUnit() internal view returns (uint256) {
        return 10 ** nativeDecimals;
    }

    // get next tokenId for _mint
    function _getNextTokenId() internal virtual returns (uint256) {
        uint tokenId = minted;
       if (tokenId > totalNativeSupply) {
            // random tokenId from _burntToken
            require (_burntTokens.length > 0, "There is no available ID for minting");
            
            uint256 slot = uint(keccak256(abi.encodePacked(minted,block.number))) % _burntTokens.length;

            tokenId = _burntTokens[slot];

            _burntTokens[slot] = _burntTokens[_burntTokens.length - 1];
            _burntTokens.pop();             
        } 
        return tokenId;
    }

    // befor_mint
    function _afterMint(uint tokenId) internal virtual  { }
    
    function _beforeBurn(uint tokenId) internal virtual {
        delete getApproved[tokenId];
    }
    function _afterBurn(uint tokenId) internal virtual { 
        _burntTokens.push(uint32(tokenId));
    }
    
    function _beforeTransfer(address from, address to, uint256 amount) internal virtual {}
    function _afterTransfer(address from, address to, uint256 amount) internal virtual {}


    function _mint(address to, uint256 tokenId) internal virtual {
       if (to == address(0) || whitelist[to]) {
            revert InvalidRecipient();
        }

        unchecked {
            minted++;
        }

        if (_tokenDetail[tokenId].owner != address(0)) {
            revert AlreadyExists();
        }

        uint32[] storage toTokenList = _ownedTokens[to];
        TokenDetail storage tokenDetail = _tokenDetail[tokenId];

        tokenDetail.owner = to;        
        tokenDetail.ownedTokensIndex = uint32(toTokenList.length);
        tokenDetail.allTokensIndex = uint32(_allTokens.length);

        toTokenList.push(uint32(tokenId));
        _allTokens.push(uint32(tokenId));

        _afterMint(tokenId);                           
 
        emit Transfer(address(0), to, tokenId); 
    }

    function _mint(address to) internal virtual {
        if (to == address(0) || whitelist[to]) {
            revert InvalidRecipient();
        }

        unchecked {
            minted++;
        }

        uint256 tokenId = _getNextTokenId();

        // This cannot happend
        if (_tokenDetail[tokenId].owner != address(0)) {
            revert AlreadyExists();
        }

        uint32[] storage toTokenList = _ownedTokens[to];
        TokenDetail storage tokenDetail = _tokenDetail[tokenId];

        tokenDetail.owner = to;        
        tokenDetail.ownedTokensIndex = uint32(toTokenList.length);
        tokenDetail.allTokensIndex = uint32(_allTokens.length);

        toTokenList.push(uint32(tokenId));
        _allTokens.push(uint32(tokenId));

        _afterMint(tokenId);                           
 
        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Internally burns a token from a given owner's balance. This function removes the last
     * token owned by the specified address, clears any approvals for this token, and updates the
     * contract's internal state to reflect the burn. It is designed to support token management
     * policies by allowing tokens to be effectively removed from circulation.
     * 
     * The function performs several key operations:
     * - Validates that the `from` address is not the zero address, to prevent burning from an
     *   invalid address.
     * - Clears the approval for the token being burned to ensure it cannot be transferred post-burn.
     * - Updates internal mappings and arrays to remove the token from the owner's list of tokens
     *   and the contract's overall enumeration of tokens.
     * - Adjusts the token's details to reflect that it no longer has an owner and is no longer
     *   part of the active token set.
     * 
     * This mechanism is essential for maintaining the integrity of the token ownership and
     * supply, allowing for tokens to be retired or removed in response to specific conditions
     * or rules defined by the contract.
     *
     * @param from The address of the token owner from which the token will be burned. This address
     * must currently own at least one token, and cannot be the zero address.
     *
     */
    function _burn(address from) internal virtual {
        if (from == address(0)) {
            revert InvalidSender();
        }

        // Clear approvals
        uint256 tokenId = _ownedTokens[from][_ownedTokens[from].length - 1];

        _beforeBurn(tokenId);

        TokenDetail storage tokenDetail = _tokenDetail[tokenId];
        uint32[] storage fromTokenList = _ownedTokens[from];
                
        uint32 tokenIndex = tokenDetail.ownedTokensIndex;
        uint32 lastToken = fromTokenList[fromTokenList.length - 1];
        if (lastToken != tokenId) {
            fromTokenList[tokenIndex] = lastToken;
            _tokenDetail[lastToken].ownedTokensIndex = tokenIndex;
        }
        fromTokenList.pop();
        
        // _removeTokenFromALLTokensEnumeration
        uint32 lastAllToken = _allTokens[_allTokens.length - 1];
        uint32 allTokensIndex = tokenDetail.allTokensIndex;
        _allTokens[allTokensIndex] = lastAllToken;
        _tokenDetail[lastAllToken].allTokensIndex = allTokensIndex;

        tokenDetail.owner  = address(0);       
        tokenDetail.allTokensIndex = 0;
        tokenDetail.ownedTokensIndex = 0;
        
        _allTokens.pop();

        _afterBurn(tokenId);

        emit Transfer(from, address(0), tokenId);
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
        return _tokenDetail[tokenId].owner != address(0);
    }

    /**
     * @dev Returns whether 'tokenId' valid.
     *
     * TokenId must be fit inside uint32 (i.e. < 2**32) and between 1 and totalNativeSize
     *
     */
    function _valid(uint256 tokenId) internal view virtual returns (bool) {
        return (tokenId < 2**32) && (tokenId > 0) && (tokenId <= totalNativeSupply);
    }

    /**
     * @dev Returns the total number of active ERC721 token currently in circulation within the contract.
     *
     * This count excludes any tokens that have been burned, providing a precise measure of the
     * net supply of ERC721 tokens that remain valid and owned by addresses.
     */
    function totalERC721Supply() public view returns (uint256) {
        return _allTokens.length;
    }

    /**
    * @dev Returns the balance of ERC721 tokens owned by a specified address. This function
    * calculates the owner's token balance based on the assumption that each token is 
    * represented as a unit in a larger balance, factoring in the contract's defined unit size.
    * It is designed to provide compatibility with ERC721's standard `balanceOf` function by
    * adapting it to a hybrid token model where ownership might be fractionalized or represented
    * differently.
    *
    * If the owner's address is whitelisted, this function returns 0, under the assumption that
    * whitelisted addresses cannot hold ERC721 token and only interct with ERC20 token.
    *
    * @param owner The address to query the balance of ERC721 tokens for.
    * @return uint256 The number of ERC721 tokens owned by the specified address. This balance
    * is calculated by dividing the total balance (which may represent fractional ownership in
    * the contract) by the defined unit size, excluding whitelisted addresses by returning 0 for them.
    */
    function ERC721BalanceOf(address owner) public view returns (uint256) {
        return whitelist[owner] ? 0 : (balanceOf[owner] / _getUnit());
    }

    /**
    * @dev Retrieves the token ID at a specific index of the tokens owned by a given address.
    * This function is essential for enumerating tokens owned by an address when order or
    * specific positioning of tokens is relevant. It allows for ordered access to an owner's
    * tokens, facilitating operations like displaying tokens in a UI or performing actions on
    * specific tokens based on their order in the owner's collection.
    *
    * The function checks that the requested index is valid for the owner's balance of tokens
    * to prevent out-of-bounds access. This ensures that only existing tokens are queried,
    * safeguarding against invalid requests and potential errors in calling contracts or 
    * applications.
    *
    * @param owner The address whose tokens are being queried. This address is used to identify
    * the collection of tokens owned within the contract.
    * @param index The zero-based index of the token to retrieve from the owner's list of tokens.
    * This index must be less than the total number of tokens owned by the address, as returned
    * by `ERC721BalanceOf`.
    * @return uint256 The token ID located at the specified index within the owner's list of tokens.
    * This ID represents a specific token owned by the address and can be used for further
    * interactions or queries related to that token.
    *
    * Requirements:
    * - The `index` must be within the range of the total tokens owned by the `owner`, as
    *   determined by `ERC721BalanceOf`. If the index is out of bounds, the function reverts
    *   with an "Owner index out of bounds" error.
    */
    function tokenOfOwnerByIndex(address owner, uint256 index) public view returns (uint256) {
        require(index < ERC721BalanceOf(owner), "Owner index out of bounds");
        return uint256(_ownedTokens[owner][index]);
    }


    /**
    * @dev Retrieves a list of ERC721 token IDs owned by a specified address. This function provides
    * a comprehensive view of all active tokens currently associated with the owner's address,
    * enabling external entities to query and interact with token ownership information.
    *
    * This is particularly useful for interfaces and applications that require a complete
    * inventory of an address's holdings within this contract, such as wallets, marketplaces,
    * or analytics tools. By returning an array of token IDs, it allows for easy integration
    * and manipulation in client-side applications or other smart contracts that may need to
    * interact with owned tokens.
    *
    * @param owner The address of the token owner whose token IDs are being queried.
    * @return uint256[] An array containing the IDs of all tokens owned by the specified address.
    * The array is dynamically sized based on the owner's current balance of tokens, ensuring
    * an accurate and up-to-date listing of ownership.
    */
    function ownedBy(address owner) external view returns (uint256[] memory) {        
        uint256 balance = ERC721BalanceOf(owner);              
        uint256[] memory tokens = new uint256[](balance);
        uint32[] storage ownedTokens = _ownedTokens[owner];
        for (uint256 i=0; i < balance; i++) {
            tokens[i] = uint256(ownedTokens[i]);
        }
        return tokens;
    }

    /**
    * @dev Sets a specific token as the last owned token for the calling user, affecting the order
    * in which tokens are considered for burning due to the FILO (First-In-Last-Out) queue mechanism.
    * This function allows users to strategically select which NFT will be burned first in transactions
    * that involve token consumption.
    * 
    * The operation swaps the positions of the specified token and the current last token in the user's
    * ownership list. This is particularly useful in scenarios where the user wishes to preserve certain
    * NFTs from being burned in the immediate next transaction that triggers a burn.
    * 
    * Requirements:
    * - The caller must be the owner of the `tokenId` specified.
    * - `tokenId` must represent a valid and owned NFT within the contract.
    * 
    * @param tokenId The unique identifier of the token to set as the last owned token. This token
    * will be moved to the end of the caller's owned tokens list, making it the next in line to be
    * burned in a FILO queue mechanism.
    */   
    function setLastOwnedTokenId(uint256 tokenId) external {
        require (ownerOf(tokenId) == msg.sender, "Token doesnot belong to sender");
        uint256 lastTokenId = getLastOwnedTokenId(msg.sender);
        TokenDetail storage tokenDetail = _tokenDetail[tokenId];
        TokenDetail storage lastDetail  = _tokenDetail[lastTokenId];

        _ownedTokens[msg.sender][lastDetail.ownedTokensIndex] = uint32(tokenId);
        _ownedTokens[msg.sender][tokenDetail.ownedTokensIndex] = uint32(lastTokenId);

        lastDetail.ownedTokensIndex = tokenDetail.ownedTokensIndex;
        tokenDetail.ownedTokensIndex = uint32(_ownedTokens[msg.sender].length - 1);
    }

    function setOwnedTokenIdByIndex(uint256 index, uint256 tokenId) external {
        require (ownerOf(tokenId) == msg.sender, "Token doesnot belong to sender");
        uint256 indexId = tokenOfOwnerByIndex(msg.sender, index);
        TokenDetail storage tokenDetail = _tokenDetail[tokenId];
        TokenDetail storage indexDetail = _tokenDetail[indexId];

        _ownedTokens[msg.sender][indexDetail.ownedTokensIndex] = uint32(tokenId);
        _ownedTokens[msg.sender][tokenDetail.ownedTokensIndex] = uint32(indexId);

        indexDetail.ownedTokensIndex = tokenDetail.ownedTokensIndex;
        tokenDetail.ownedTokensIndex = uint32(index);
    }

    /**
    * @dev Publicly retrieves the ID of the last token owned by a specified address, following
    * the FILO (First-In-Last-Out) queue logic. This function enables external entities, including
    * users and other contracts, to identify the most recently acquired or assigned token for a
    * given owner. It's particularly useful for understanding which token will be burnt based 
    * on the FILO queue mechanism.
    *
    * Requirements:
    * - The `owner` must possess at least one token within this contract. If the queried owner
    *   has no tokens, the function reverts with a "Owner has no tokens" error, ensuring calls
    *   to this function are meaningful and pertain to actual owners.
    *
    * @param owner The address of the token owner whose last owned token ID is requested.
    * @return uint256 The ID of the last token owned by the given address, providing insight
    * on the owner's next token to be burnt based on the FILO queue mechanism.
    *
    */
	function getLastOwnedTokenId(address owner) public view returns (uint256) {
		require(_ownedTokens[owner].length > 0, "Owner has no tokens");
		return _ownedTokens[owner][_ownedTokens[owner].length - 1];
	}

}
// File: contracts/Cube404.sol

pragma solidity ^0.8.21;



contract Cube404 is ERC404C {

    string public baseTokenURI = "https://ipfs.io/ipfs/Qme1oy5af1RaCgxztACC8pbyuNR3HajRYcMAHRMyLQ39S7/";

    uint public immutable legendarySupply = 1; 
    uint public immutable epicSupply      = 9; 
    uint public immutable rareSupply      = 90; 
    uint public legendaryMinted;
    uint public epicMinted;
    uint public rareMinted;

    uint public deckSize = 1000;

    // variable for radom tokenId generation
    uint private slotn; 
    mapping (uint256 => uint256) private slots;
    mapping (uint256 => uint256) private legendarySlots;
    mapping (uint256 => uint256) private epicSlots;
    mapping (uint256 => uint256) private rareSlots;

    constructor() ERC404C("Cube404", "CUBE", 18, 21, deckSize, msg.sender) {
        slotn = totalNativeSupply - customMintSupply();
        balanceOf[msg.sender] = deckSize * _getUnit();
        emit ERC20Transfer(address(0x0), msg.sender, deckSize * _getUnit());
    }

    function _beforeTransfer(address from, address to, uint256 amount) internal view override {
        address _owner = owner();
        if (from == _owner && to != _owner) {
            // make sure that there is always enough token for reward distribution
            uint256 balaceAfterTransfer = balanceOf[_owner] - amount;
            require(balaceAfterTransfer >= customMintDemand() * _getUnit(), "Not enough token");
        }
    }

    function customMintSupply() public pure returns (uint256) { return legendarySupply + epicSupply + rareSupply; }
    function customMintMinted() public view returns (uint256) { return legendaryMinted + epicMinted + rareMinted; } 
    function customMintDemand() public view returns (uint256) { return customMintSupply() - customMintMinted(); }

    function checkWhiteList(address addr) public view returns (bool) { return whitelist[addr]; }

    function _afterBurn(uint256 tokenId) internal override {
        // push burn tokenId into slots
        slots[slotn] = tokenId;
        slotn += 1;
    }

    function _getNextTokenId() internal override returns (uint256) {
        // random id from slots
        uint location = uint(keccak256(abi.encodePacked(minted,block.number))) % slotn; 
        uint id = slots[location];
        if (id == 0) id = location + 1;
        slotn -= 1;
        slots[location] = (slots[slotn] == 0) ? (slotn + 1) : slots[slotn];       
        return (id);
    }

    function mintRareTo(address to) public onlyOwner {
        require(rareMinted < rareSupply, "Rare is fully minted");

        uint256 _slotn    = rareSupply - rareMinted;
        uint256 location = uint(keccak256(abi.encodePacked(minted,block.number))) % _slotn;
        uint256 id = rareSlots[location];
        if (id == 0) id = 900 + location + 1;
        rareMinted += 1;

        rareSlots[location] = (rareSlots[_slotn-1] == 0) 
                                ? 900 + _slotn
                                : rareSlots[_slotn-1];

        balanceOf[to] += _getUnit();
        balanceOf[msg.sender] -= _getUnit();

        _mint(to, id);        
    }


    function mintEpicTo(address to) public onlyOwner {
        require(epicMinted < epicSupply, "Epic is fully minted");

        uint256 _slotn    = epicSupply - epicMinted;
        uint256 location = uint(keccak256(abi.encodePacked(minted,block.number))) % _slotn;
        uint256 id = epicSlots[location];
        if (id == 0) id = 990 + location + 1;
        epicMinted += 1;

        epicSlots[location] = (epicSlots[_slotn-1] == 0) 
                                ? 990 + _slotn
                                : epicSlots[_slotn-1];

        balanceOf[to] += _getUnit();
        balanceOf[msg.sender] -= _getUnit();
        _mint(to, id);
    }

    function mintLegendaryTo(address to) public onlyOwner {
        require(legendaryMinted < legendarySupply, "Legendary is fully minted");
        legendaryMinted += 1;
        balanceOf[to] += _getUnit();
        balanceOf[msg.sender] -= _getUnit();
        _mint(to, 1000);
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return string.concat(baseTokenURI, Strings.toString(tokenId), ".json" );
    }

    /// @notice Function native approvals
    /// provide option for Metamask user to call setApprovalForAll
    function setApprovalForAllMetaMask(address operator, bool approved) public {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }
}