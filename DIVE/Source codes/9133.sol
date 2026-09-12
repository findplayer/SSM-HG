// Sources flattened with hardhat v2.19.4 https://hardhat.org

// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts/utils/math/Math.sol@v4.9.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/math/Math.sol)

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
    function mulDiv(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
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
                // Solidity will revert if denominator == 0, unlike the div opcode on its own.
                // The surrounding unchecked block does not change this fact.
                // See https://docs.soliditylang.org/en/latest/control-structures.html#checked-or-unchecked-arithmetic.
                return prod0 / denominator;
            }

            // Make sure the result is less than 2^256. Also prevents denominator == 0.
            require(denominator > prod1, "Math: mulDiv overflow");

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
    function mulDiv(uint256 x, uint256 y, uint256 denominator, Rounding rounding) internal pure returns (uint256) {
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
            return result + (rounding == Rounding.Up && 10 ** result < value ? 1 : 0);
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
     * @dev Return the log in base 256, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result << 3) < value ? 1 : 0);
        }
    }
}


// File @openzeppelin/contracts/utils/math/SignedMath.sol@v4.9.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.8.0) (utils/math/SignedMath.sol)

pragma solidity ^0.8.0;

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


// File @openzeppelin/contracts/utils/Strings.sol@v4.9.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/Strings.sol)

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
     * @dev Converts a `int256` to its ASCII `string` decimal representation.
     */
    function toString(int256 value) internal pure returns (string memory) {
        return string(abi.encodePacked(value < 0 ? "-" : "", toString(SignedMath.abs(value))));
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

    /**
     * @dev Returns true if the two strings are equal.
     */
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}


// File @openzeppelin/contracts/utils/cryptography/ECDSA.sol@v4.9.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/cryptography/ECDSA.sol)

pragma solidity ^0.8.0;

/**
 * @dev Elliptic Curve Digital Signature Algorithm (ECDSA) operations.
 *
 * These functions can be used to verify that a message was signed by the holder
 * of the private keys of a given address.
 */
library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV // Deprecated in v4.8
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
    function tryRecover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address, RecoverError) {
        bytes32 s = vs & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        uint8 v = uint8((uint256(vs) >> 255) + 27);
        return tryRecover(hash, v, r, s);
    }

    /**
     * @dev Overload of {ECDSA-recover} that receives the `r and `vs` short-signature fields separately.
     *
     * _Available since v4.2._
     */
    function recover(bytes32 hash, bytes32 r, bytes32 vs) internal pure returns (address) {
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
    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address, RecoverError) {
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
    function recover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address) {
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
    function toEthSignedMessageHash(bytes32 hash) internal pure returns (bytes32 message) {
        // 32 is the length in bytes of hash,
        // enforced by the type signature above
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x00, "\x19Ethereum Signed Message:\n32")
            mstore(0x1c, hash)
            message := keccak256(0x00, 0x3c)
        }
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
    function toTypedDataHash(bytes32 domainSeparator, bytes32 structHash) internal pure returns (bytes32 data) {
        /// @solidity memory-safe-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, "\x19\x01")
            mstore(add(ptr, 0x02), domainSeparator)
            mstore(add(ptr, 0x22), structHash)
            data := keccak256(ptr, 0x42)
        }
    }

    /**
     * @dev Returns an Ethereum Signed Data with intended validator, created from a
     * `validator` and `data` according to the version 0 of EIP-191.
     *
     * See {recover}.
     */
    function toDataWithIntendedValidatorHash(address validator, bytes memory data) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x00", validator, data));
    }
}


// File @openzeppelin/contracts/interfaces/IERC1271.sol@v4.9.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (interfaces/IERC1271.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC1271 standard signature validation method for
 * contracts as defined in https://eips.ethereum.org/EIPS/eip-1271[ERC-1271].
 *
 * _Available since v4.1._
 */
interface IERC1271 {
    /**
     * @dev Should return whether the signature provided is valid for the provided data
     * @param hash      Hash of the data to be signed
     * @param signature Signature byte array associated with _data
     */
    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4 magicValue);
}


// File @openzeppelin/contracts/utils/cryptography/SignatureChecker.sol@v4.9.2

// Original license: SPDX_License_Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (utils/cryptography/SignatureChecker.sol)

pragma solidity ^0.8.0;


/**
 * @dev Signature verification helper that can be used instead of `ECDSA.recover` to seamlessly support both ECDSA
 * signatures from externally owned accounts (EOAs) as well as ERC1271 signatures from smart contract wallets like
 * Argent and Gnosis Safe.
 *
 * _Available since v4.1._
 */
library SignatureChecker {
    /**
     * @dev Checks if a signature is valid for a given signer and data hash. If the signer is a smart contract, the
     * signature is validated against that smart contract using ERC1271, otherwise it's validated using `ECDSA.recover`.
     *
     * NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function can thus
     * change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidSignatureNow(address signer, bytes32 hash, bytes memory signature) internal view returns (bool) {
        (address recovered, ECDSA.RecoverError error) = ECDSA.tryRecover(hash, signature);
        return
            (error == ECDSA.RecoverError.NoError && recovered == signer) ||
            isValidERC1271SignatureNow(signer, hash, signature);
    }

    /**
     * @dev Checks if a signature is valid for a given signer and data hash. The signature is validated
     * against the signer smart contract using ERC1271.
     *
     * NOTE: Unlike ECDSA signatures, contract signatures are revocable, and the outcome of this function can thus
     * change through time. It could return true at block N and false at block N+1 (or the opposite).
     */
    function isValidERC1271SignatureNow(
        address signer,
        bytes32 hash,
        bytes memory signature
    ) internal view returns (bool) {
        (bool success, bytes memory result) = signer.staticcall(
            abi.encodeWithSelector(IERC1271.isValidSignature.selector, hash, signature)
        );
        return (success &&
            result.length >= 32 &&
            abi.decode(result, (bytes32)) == bytes32(IERC1271.isValidSignature.selector));
    }
}


// File contracts/interfaces/internal/IDecaCollection.sol

// Original license: SPDX_License_Identifier: MIT

pragma solidity ^0.8.17;

struct Recipient {
  address payable recipient;
  uint16 bps;
}

interface IDecaCollection {
  error InvalidTokenId();
  error OnlyCreator();
  error OnlyMinterOrCreator();
  error NotTokenOwnerOrApproved();
  error ERC20SplitFailed();
  error TotalBpsMustBe10000();
  error EthTransferFailed();

  /**
   * @notice Emitted when ETH is transferred.
   * @param account The address of the account which received the ETH.
   * @param amount The amount of ETH transferred.
   */
  event ETHTransferred(address indexed account, uint256 amount);

  /**
   * @notice Emitted when an ERC20 token is transferred.
   * @param erc20Contract The address of the ERC20 contract.
   * @param account The address of the account which received the ERC20.
   * @param amount The amount of ERC20 transferred.
   */
  event ERC20Transferred(address indexed erc20Contract, address indexed account, uint256 amount);

  /**
   * @notice Emitted when the token URI is set on a token.
   * @param tokenId The id of the token.
   * @param tokenURI The token URI of the token.
   */
  event TokenUriSet(uint256 indexed tokenId, string tokenURI);

  /**
   * @notice Emitted when the treasury address is updated.
   * @param treasury The address of the new treasury.
   */
  event TreasuryUpdated(address indexed treasury);

  /**
   * @notice Emitted when the royalty bps is updated.
   * @param royaltyBps The royalty bps.
   */
  event RoyaltyBpsUpdated(uint256 royaltyBps);

  function initialize(
    address factory_,
    address creator_,
    address roleAuthority_,
    string calldata name_,
    string calldata symbol_,
    Recipient[] calldata recipients
  ) external;

  function creator() external view returns (address);

  function exists(uint256 tokenId) external view returns (bool);

  function mint(address to, uint256 tokenId) external;

  function burn(uint256 tokenId) external;

  function mintTimestamps(uint256 tokenId) external view returns (uint256);

  function setRecipients(Recipient[] calldata recipients) external;

  function setTreasuryAddress(address treasury_) external;

  function setRoyaltyBps(uint256 royaltyBps_) external;

  function getRecipients() external view returns (Recipient[] memory);

  function royaltyInfo(uint256, uint256 _salePrice) external view returns (address receiver, uint256 royaltyAmount);
}


// File contracts/deca-collections/libraries/MintStructsV3.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title MintStructs
 */
library MintStructsV3 {
    /**
     * @notice Payslip is the struct for a payout on settlement.
     * @dev Payslips are paid out in order, if there is not enough balance to pay out the next payslip, the settlement fails.
     * @param amountInWei Amount to pay out in wei
     * @param recipient Address to pay out to
     */
    struct Payslip {
        address recipient;
        uint256 amountInWei;
    }

    /**
     * @notice ListingInfo is the struct for a taker ask/bid order. It contains the parameters required for a direct purchase.
     * @dev ListingInfo struct is matched against a MintPass struct at the protocol level during settlement.
     * @param nonce Nonce to ensure listing signature is not re-used
     * @param creatorAddress Address of the creator accepting the bid or listing the item
     * @param collectionAddress Address to mint the token on
     * @param tokenId Id of the token to mint
     * @param priceInWei Price to mint the token for
     * @param expiresAt Timestamp the listing expires at
     * @param allowedTakers Array of addresses allowed to take the order
     * @param payslips Array of payslips to be paid out on settlement
     */
    struct ListingInfo {
        uint256 nonce;
        address creatorAddress;
        address collectionAddress;
        uint256 tokenId;
        uint256 priceInWei;
        uint256 expiresAt;
        address[] allowedTakers;
        Payslip[] payslips;
    }

    /**
     * @notice To enable gasless cancellation of listings and bids, we provide a fast expiring signature that is required during settlement and acts as an off-chain mint pass.
     *        If a creator tells Deca they want to cancel their listing/bid acceptance, we mark it as cancelled internally and refuse to provide a signature for settlement.
     *        In case a creator wants to cancel their listing/bid acceptance without going through Deca in case the expiry time isn't short enough, they can do so on chain.
     * @dev listingSignatureHash acts as a nonce, if it's already been used the settlement fails.
     * @param expiresAt Timestamp signature expires at
     * @param listingSignatureHash ListingInfo struct is matched against a MintPass struct at the protocol level during settlement.
     * @param signer Address owned by Deca used to sign the message
     */
    struct MintPass {
        uint256 expiresAt;
        bytes32 listingSignatureHash;
        address signer;
    }

    /**
     * @notice A summary of the settlement data required to mint on demand.
     * @param listingSignature Signature for the listing info
     * @param mintPassSignature Signature for the mint pass
     * @param listing ListingInfo struct, signed by creator
     * @param mintPass MintPass struct, signed by Deca
     */
    struct Settlement {
        bytes listingSignature;
        bytes mintPassSignature;
        ListingInfo listing;
        MintPass mintPass;
    }

    /**
     * @notice CollectionInfo is the struct that provides info about a collection being created.
     * @param signer Address owned by Deca used to sign the message
     * @param nonce Nonce for the collection, used to generate the collection address
     * @param collectionName Name of the collection being created
     * @param collectionSymbol Symbol of the collection being created
     * @param royaltyRecipients Array of secondary market royalty recipients
     */
    struct CollectionInfo {
        string collectionName;
        string collectionSymbol;
        uint96 nonce;
        address signer;
        Recipient[] royaltyRecipients;
    }

    /**
     * @dev This is the type hash constant used to compute the taker order hash.
     */
    bytes32 internal constant _LISTINGINFO_TYPEHASH = keccak256(
        "ListingInfo(" "uint256 nonce," "address creatorAddress," "address collectionAddress," "uint256 tokenId,"
        "uint256 priceInWei," "uint256 expiresAt," "address[] allowedTakers," "Payslip[] payslips" ")"
        "Payslip(address recipient,uint256 amountInWei)"
    );

    /**
     * @dev This is the type hash constant used to compute the payslip hash.
     */
    bytes32 internal constant _PAYSLIP_TYPEHASH = keccak256("Payslip(" "address recipient," "uint256 amountInWei" ")");

    /**
     * @dev This is the type hash constant used to compute the mint pass hash.
     */
    bytes32 internal constant _MINTPASS_TYPEHASH =
        keccak256("MintPass(" "uint256 expiresAt," "bytes32 listingSignatureHash," "address signer" ")");

    /**
     * @dev This is the type hash constant used to compute the collection info hash.
     */
    bytes32 internal constant _COLLECTIONINFO_TYPEHASH = keccak256(
        "CollectionInfo(" "string collectionName," "string collectionSymbol," "uint96 nonce," "address signer,"
        "Recipient[] royaltyRecipients" ")" "Recipient(address recipient,uint16 bps)"
    );

    /**
     * @dev This is the type hash constant used to compute the recipient hash.
     */
    bytes32 internal constant _RECIPIENT_TYPEHASH = keccak256("Recipient(" "address recipient," "uint16 bps" ")");

    /**
     * @notice This function is used to compute the EIP712 hash for an ListingInfo struct.
     * @param listingInfo ListingInfo struct
     * @return listingInfoHash Hash of the ListingInfo struct
     */
    function hash(ListingInfo memory listingInfo) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _LISTINGINFO_TYPEHASH,
                listingInfo.nonce,
                listingInfo.creatorAddress,
                listingInfo.collectionAddress,
                listingInfo.tokenId,
                listingInfo.priceInWei,
                listingInfo.expiresAt,
                keccak256(abi.encodePacked(listingInfo.allowedTakers)),
                _encodePayslips(listingInfo.payslips)
            )
        );
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a Payslip struct.
     * @param payslip Payslip struct
     * @return payslipHash Hash of the Payslip struct
     */
    function _encodePayslip(Payslip memory payslip) internal pure returns (bytes32) {
        return keccak256(abi.encode(_PAYSLIP_TYPEHASH, payslip.recipient, payslip.amountInWei));
    }

    /**
     * @notice This function is used to compute the EIP712 hash for an array of Payslip structs.
     * @param payslips Array of Payslip structs
     * @return payslipsHash Hash of the Payslip structs
     */
    function _encodePayslips(Payslip[] memory payslips) internal pure returns (bytes32) {
        bytes32[] memory encodedPayslips = new bytes32[](payslips.length);
        for (uint256 i = 0; i < payslips.length; i++) {
            encodedPayslips[i] = _encodePayslip(payslips[i]);
        }

        return keccak256(abi.encodePacked(encodedPayslips));
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a MintPass struct.
     * @param mintPass MintPass struct
     * @return mintPassHash Hash of the MintPass struct
     */
    function hash(MintPass memory mintPass) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(_MINTPASS_TYPEHASH, mintPass.expiresAt, mintPass.listingSignatureHash, mintPass.signer)
        );
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a CollectionInfo struct.
     * @param collectionInfo CollectionInfo struct
     * @return collectionInfoHash Hash of the CollectionInfo struct
     */
    function hash(CollectionInfo memory collectionInfo) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _COLLECTIONINFO_TYPEHASH,
                keccak256(bytes(collectionInfo.collectionName)),
                keccak256(bytes(collectionInfo.collectionSymbol)),
                collectionInfo.nonce,
                collectionInfo.signer,
                _encodeRecipients(collectionInfo.royaltyRecipients)
            )
        );
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a Recipient struct.
     * @param recipient Recipient struct
     * @return recipientHash Hash of the Recipient struct
     */
    function _encodeRecipient(Recipient memory recipient) internal pure returns (bytes32) {
        return keccak256(abi.encode(_RECIPIENT_TYPEHASH, recipient.recipient, recipient.bps));
    }

    /**
     * @notice This function is used to compute the EIP712 hash for an array of Recipient structs.
     * @param recipients Array of Recipient structs
     * @return recipientsHash Hash of the Recipient structs
     */
    function _encodeRecipients(Recipient[] memory recipients) internal pure returns (bytes32) {
        bytes32[] memory encodedRecipients = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            encodedRecipients[i] = _encodeRecipient(recipients[i]);
        }

        return keccak256(abi.encodePacked(encodedRecipients));
    }
}


// File contracts/interfaces/internal/IRoleAuthority.sol

// Original license: SPDX_License_Identifier: MIT

pragma solidity ^0.8.17;

interface IRoleAuthority {
  function isOperator(address _address) external view returns (bool);

  function is721Minter(address _address) external view returns (bool);

  function isMintPassSigner(address _address) external view returns (bool);

  function isPosterMinter(address _address) external view returns (bool);

  function isPosterSigner(address _address) external view returns (bool);
}


// File contracts/interfaces/internal/ISettlementValidatorV3.sol

// Original license: SPDX_License_Identifier: MIT

pragma solidity ^0.8.17;

interface ISettlementValidatorV3 {
    error ChainIdInvalid();
    error SignatureRepeated();
    error MintPassExpired();
    error UnauthorizedMintPassSigner();
    error MintPassSignatureInvalid();
    error NotAuthorized();
    error TokenAlreadyCreated();
    error UnauthorizedCollectionInfoSigner();
    error CollectionInfoSignatureInvalid();
    error ListingExpired();
    error ListingSignatureInvalid();
    error UnauthorizedListingSigner();
    error SignatureMatchedOrCancelled();
    error NonMinterSettle();
    error ListingPriceNotMet();
    error SignatureHashMismatch();

    function validateSettlement(MintStructsV3.Settlement calldata settlement, uint256 msgValue, address msgSender)
        external
        returns (bytes32 hash);

    function validateCollectionInfo(MintStructsV3.CollectionInfo calldata collectionInfo, bytes calldata signature)
        external
        view;

    function cancelListing(MintStructsV3.ListingInfo calldata listing) external;

    event ListingCanceled(bytes32 indexed listingId);
}


// File contracts/deca-collections/SettlementValidatorV3.sol

// Original license: SPDX_License_Identifier: MIT

pragma solidity ^0.8.17;




/**
 * @notice Validates EIP712 off-chain signatures for mint on demand DecaCollection NFTs
 * @author 0x-jj, j6i
 */
contract SettlementValidatorV3 is ISettlementValidatorV3 {
    using MintStructsV3 for MintStructsV3.ListingInfo;
    using MintStructsV3 for MintStructsV3.MintPass;
    using MintStructsV3 for MintStructsV3.CollectionInfo;

    /*//////////////////////////////////////////////////////////////
                              STORAGE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice RoleAuthority contract to determine whether an address has some admin role.
     */
    IRoleAuthority public immutable roleAuthority;

    /**
     * @notice The chain id of the network this contract is deployed on.
     */
    uint256 public immutable chainId;

    /**
     * @notice The EIP-712 domain separator.
     */
    bytes32 public immutable domainSeparator;

    /**
     * @notice A mapping of listing hashes to whether they have been used .
     */
    mapping(bytes32 => bool) public listingMatchedOrCancelled;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address _roleAuthority, string memory name, string memory version) {
        /* 
      There is no way to update the domain separator, as the contract has no owner or admin.

      If there is a network fork that changes the chain id, a new contract needs to be deployed
      and minting ability of the old one must be revoked.

      In case of a new contract deployment, the version of the new contract MUST be updated,
      so that filled orders from past versions are not valid.  
        */
        domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes(version)),
                block.chainid,
                address(this)
            )
        );
        chainId = block.chainid;
        roleAuthority = IRoleAuthority(_roleAuthority);
    }

    /*//////////////////////////////////////////////////////////////
                                 EXTERNAL
    //////////////////////////////////////////////////////////////*/

    function cancelListing(MintStructsV3.ListingInfo calldata listing) external {
        if (msg.sender != listing.creatorAddress) {
            revert NotAuthorized();
        }
        bytes32 listingHash = listing.hash();
        if (listingMatchedOrCancelled[listingHash]) {
            revert SignatureMatchedOrCancelled();
        }
        listingMatchedOrCancelled[listingHash] = true;
        emit ListingCanceled(listingHash);
    }

    function validateSettlement(MintStructsV3.Settlement calldata settlement, uint256 msgValue, address msgSender)
        external
        returns (bytes32 listingHash)
    {
        // If there are specified allowed takers, check that the msgSender is one of them
        // If not, it's a buy now, and anyone can take it
        if (
            !containsAddress(settlement.listing.allowedTakers, msgSender)
                && settlement.listing.allowedTakers.length != 0
        ) {
            revert NonMinterSettle();
        }

        if (!roleAuthority.is721Minter(msg.sender)) {
            revert NotAuthorized();
        }

        if (msgValue < settlement.listing.priceInWei) {
            revert ListingPriceNotMet();
        }

        IDecaCollection collection = IDecaCollection(settlement.listing.collectionAddress);

        listingHash = settlement.listing.hash();

        // Check listing hash hasn't been used
        if (listingMatchedOrCancelled[listingHash]) {
            revert SignatureMatchedOrCancelled();
        }

        // Mark listing hash as used
        listingMatchedOrCancelled[listingHash] = true;

        if (keccak256(settlement.listingSignature) != settlement.mintPass.listingSignatureHash) {
            revert SignatureHashMismatch();
        }

        // Check that the listing info has been signed by the expected address
        if (!_verifySignature(listingHash, settlement.listingSignature, settlement.listing.creatorAddress)) {
            revert ListingSignatureInvalid();
        }

        // Check that the mint pass has been signed by the expected address
        if (!_verifySignature(settlement.mintPass.hash(), settlement.mintPassSignature, settlement.mintPass.signer)) {
            revert MintPassSignatureInvalid();
        }

        // Check token id hasn't been created already
        if (collection.mintTimestamps(settlement.listing.tokenId) > 0) {
            revert TokenAlreadyCreated();
        }

        // Check creator of the collection is the same as the address signing the listing info
        if (collection.creator() != settlement.listing.creatorAddress) {
            revert UnauthorizedListingSigner();
        }

        // Check listing not expired
        if (settlement.listing.expiresAt < block.timestamp) {
            revert ListingExpired();
        }

        // Check mint pass signature has not expired
        if (settlement.mintPass.expiresAt < block.timestamp) {
            revert MintPassExpired();
        }

        // Check mint pass signer is actually allowed to sign
        if (!roleAuthority.isMintPassSigner(settlement.mintPass.signer)) {
            revert UnauthorizedMintPassSigner();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 EXTERNAL VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Validates a collection info struct
     * @param collectionInfo Contains all the collection info
     * @param signature Signature used to sign the collection info
     */
    function validateCollectionInfo(MintStructsV3.CollectionInfo calldata collectionInfo, bytes calldata signature)
        external
        view
    {
        if (!roleAuthority.is721Minter(msg.sender)) {
            revert NotAuthorized();
        }

        bytes32 collectionInfoHash = collectionInfo.hash();

        // Check mint pass signer is actually allowed to sign
        if (!roleAuthority.isMintPassSigner(collectionInfo.signer)) {
            revert UnauthorizedCollectionInfoSigner();
        }

        if (!_verifySignature(collectionInfoHash, signature, collectionInfo.signer)) {
            revert CollectionInfoSignatureInvalid();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 INTERNAL VIEW
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Used to verify the chain id, compute the digest, and verify the signature.
     * @dev If chainId is not equal to the cached chain id, it would revert.
     * @param computedHash Hash of order (maker bid or maker ask) or merkle root
     * @param signature Signature of the maker
     * @param signer Signer address
     */
    function _verifySignature(bytes32 computedHash, bytes calldata signature, address signer)
        internal
        view
        returns (bool)
    {
        if (chainId == block.chainid) {
            return SignatureChecker.isValidSignatureNow(
                signer, ECDSA.toTypedDataHash(domainSeparator, computedHash), signature
            );
        } else {
            revert ChainIdInvalid();
        }
    }

    function containsAddress(address[] memory addresses, address addressToFind) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == addressToFind) {
                return true;
            }
        }
        return false;
    }
}