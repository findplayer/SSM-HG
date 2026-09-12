// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// This is the right base URI
string constant BASE_URI = "ipfs://bafybeigwdq36jrfls3fkub5abqzczrbj57dihkvtrw57z2nirums5m26b4/";

// What is the maximum an account can mint?
uint256 constant MAX_MINT = 10;

// MAX_SUPPLY is the maximum number of tokens that can be minted (1000)
uint256 constant MAX_SUPPLY = 1000;

// How much does it cost to mint?
uint256 constant MINT_PRICE = 0.06 ether;

interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

interface IERC721 is IERC165 {

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    function balanceOf(address owner) external view returns (uint256 balance);

    function ownerOf(uint256 tokenId) external view returns (address owner);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;

    function approve(address to, uint256 tokenId) external;

    function setApprovalForAll(address operator, bool _approved) external;

    function getApproved(uint256 tokenId) external view returns (address operator);

    function isApprovedForAll(address owner, address operator) external view returns (bool);
}


interface IERC721Receiver {

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}


interface IERC721Metadata is IERC721 {

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function tokenURI(uint256 tokenId) external view returns (string memory);
}


library Address {

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, "Address: low-level call failed");
    }

    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

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

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        (bool success, bytes memory returndata) = target.staticcall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return verifyCallResultFromTarget(target, success, returndata, errorMessage);
    }


    function verifyCallResultFromTarget(
        address target,
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        if (success) {
            if (returndata.length == 0) {
                require(isContract(target), "Address: call to non-contract");
            }
            return returndata;
        } else {
            _revert(returndata, errorMessage);
        }
    }

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
        if (returndata.length > 0) {
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert(errorMessage);
        }
    }
}


abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}


library Math {
    enum Rounding {
        Down, // Toward negative infinity
        Up, // Toward infinity
        Zero // Toward zero
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

    function ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b - 1) / b can overflow on addition, so we distribute.
        return a == 0 ? 0 : (a - 1) / b + 1;
    }

    function mulDiv(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 result) {
        unchecked {
            uint256 prod0; 
            uint256 prod1;
            assembly {
                let mm := mulmod(x, y, not(0))
                prod0 := mul(x, y)
                prod1 := sub(sub(mm, prod0), lt(mm, prod0))
            }
            if (prod1 == 0) {
                return prod0 / denominator;
            }

            require(denominator > prod1);

            uint256 remainder;
            assembly {
                remainder := mulmod(x, y, denominator)

                prod1 := sub(prod1, gt(remainder, prod0))
                prod0 := sub(prod0, remainder)
            }

            uint256 twos = denominator & (~denominator + 1);
            assembly {
                denominator := div(denominator, twos)

                prod0 := div(prod0, twos)

                twos := add(div(sub(0, twos), twos), 1)
            }

            prod0 |= prod1 * twos;

            uint256 inverse = (3 * denominator) ^ 2;

            inverse *= 2 - denominator * inverse; // inverse mod 2^8
            inverse *= 2 - denominator * inverse; // inverse mod 2^16
            inverse *= 2 - denominator * inverse; // inverse mod 2^32
            inverse *= 2 - denominator * inverse; // inverse mod 2^64
            inverse *= 2 - denominator * inverse; // inverse mod 2^128
            inverse *= 2 - denominator * inverse; // inverse mod 2^256

            result = prod0 * inverse;
            return result;
        }
    }


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

    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 result = 1 << (log2(a) >> 1);

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

    function sqrt(uint256 a, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = sqrt(a);
            return result + (rounding == Rounding.Up && result * result < a ? 1 : 0);
        }
    }

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

    function log2(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log2(value);
            return result + (rounding == Rounding.Up && 1 << result < value ? 1 : 0);
        }
    }

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

    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (rounding == Rounding.Up && 10**result < value ? 1 : 0);
        }
    }

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

    function log256(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log256(value);
            return result + (rounding == Rounding.Up && 1 << (result * 8) < value ? 1 : 0);
        }
    }
}

library Strings {
    bytes16 private constant _SYMBOLS = "0123456789abcdef";
    uint8 private constant _ADDRESS_LENGTH = 20;

    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                assembly {
                    mstore8(ptr, byte(mod(value, 10), _SYMBOLS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }

    function toHexString(uint256 value) internal pure returns (string memory) {
        unchecked {
            return toHexString(value, Math.log256(value) + 1);
        }
    }

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

    function toHexString(address addr) internal pure returns (string memory) {
        return toHexString(uint256(uint160(addr)), _ADDRESS_LENGTH);
    }
}

abstract contract ERC165 is IERC165 {
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}


abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }


    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


contract PixelShibellasERC721 is
    Context,
    ERC165,
    IERC721,
    IERC721Metadata,
    Ownable
{
    using Address for address;
    using Strings for uint256;

    string private _name;

    string private _symbol;

    mapping(uint => uint) private _availableTokens;

    uint256 constant _maxSupply = MAX_SUPPLY;
    uint256 private _numAvailableTokens = _maxSupply;

    mapping(uint256 => address) private _owners;

    mapping(address => uint256) private _balances;

    mapping(uint256 => address) private _tokenApprovals;

    mapping(address => mapping(address => bool)) private _operatorApprovals;

    uint8[1000] private _rarity = [
        3,
        2,
        4,
        3,
        2,
        2,
        3,
        4,
        4,
        4,
        3,
        1,
        2,
        3,
        4,
        3,
        4,
        4,
        4,
        3,
        1,
        2,
        2,
        4,
        3,
        4,
        4,
        4,
        3,
        4,
        4,
        4,
        4,
        4,
        4,
        1,
        4,
        3,
        4,
        4,
        2,
        4,
        4,
        2,
        2,
        4,
        4,
        4,
        4,
        2,
        3,
        4,
        4,
        3,
        4,
        3,
        2,
        4,
        4,
        3,
        4,
        3,
        3,
        4,
        4,
        4,
        2,
        4,
        3,
        2,
        2,
        4,
        4,
        4,
        2,
        3,
        4,
        4,
        4,
        4,
        3,
        4,
        3,
        3,
        2,
        4,
        3,
        3,
        2,
        4,
        4,
        4,
        4,
        4,
        3,
        2,
        2,
        4,
        1,
        4,
        4,
        3,
        2,
        3,
        4,
        2,
        4,
        4,
        4,
        2,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        4,
        4,
        3,
        2,
        4,
        2,
        3,
        4,
        2,
        2,
        4,
        4,
        4,
        2,
        2,
        4,
        3,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        4,
        1,
        3,
        3,
        4,
        4,
        4,
        1,
        3,
        4,
        3,
        3,
        3,
        4,
        4,
        4,
        3,
        4,
        3,
        2,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        3,
        3,
        4,
        3,
        4,
        4,
        4,
        4,
        4,
        1,
        4,
        3,
        1,
        4,
        3,
        4,
        3,
        3,
        1,
        4,
        4,
        4,
        4,
        4,
        3,
        3,
        4,
        3,
        1,
        4,
        3,
        3,
        3,
        3,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        4,
        3,
        4,
        3,
        4,
        2,
        4,
        2,
        2,
        4,
        3,
        2,
        4,
        4,
        4,
        3,
        3,
        2,
        4,
        1,
        4,
        4,
        3,
        4,
        3,
        4,
        4,
        4,
        3,
        4,
        3,
        4,
        3,
        3,
        2,
        3,
        3,
        1,
        4,
        4,
        4,
        4,
        4,
        3,
        2,
        4,
        3,
        3,
        3,
        4,
        4,
        4,
        3,
        3,
        4,
        3,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        4,
        3,
        4,
        4,
        1,
        2,
        4,
        4,
        3,
        4,
        3,
        2,
        2,
        2,
        2,
        4,
        3,
        4,
        1,
        2,
        3,
        4,
        4,
        3,
        3,
        4,
        4,
        2,
        2,
        4,
        3,
        2,
        4,
        2,
        4,
        4,
        3,
        2,
        4,
        4,
        3,
        4,
        4,
        3,
        4,
        4,
        2,
        3,
        4,
        3,
        3,
        2,
        2,
        4,
        4,
        3,
        4,
        4,
        3,
        2,
        3,
        3,
        3,
        3,
        4,
        4,
        4,
        3,
        3,
        4,
        4,
        4,
        3,
        4,
        4,
        4,
        3,
        4,
        4,
        3,
        3,
        2,
        4,
        4,
        4,
        4,
        3,
        4,
        4,
        1,
        4,
        4,
        3,
        3,
        4,
        4,
        3,
        1,
        4,
        2,
        4,
        3,
        4,
        4,
        4,
        3,
        4,
        3,
        4,
        3,
        4,
        2,
        4,
        4,
        4,
        3,
        4,
        3,
        4,
        3,
        4,
        4,
        4,
        2,
        1,
        4,
        3,
        4,
        4,
        4,
        4,
        4,
        2,
        4,
        4,
        2,
        4,
        4,
        4,
        3,
        3,
        3,
        2,
        4,
        2,
        3,
        3,
        4,
        4,
        3,
        4,
        4,
        3,
        4,
        2,
        4,
        4,
        4,
        4,
        4,
        4,
        3,
        2,
        3,
        4,
        3,
        4,
        4,
        4,
        4,
        3,
        4,
        4,
        4,
        4,
        2,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        3,
        3,
        4,
        3,
        4,
        4,
        1,
        4,
        4,
        4,
        4,
        1,
        3,
        3,
        2,
        4,
        4,
        1,
        4,
        4,
        4,
        3,
        2,
        3,
        4,
        2,
        3,
        3,
        3,
        4,
        1,
        4,
        2,
        4,
        4,
        4,
        1,
        3,
        4,
        4,
        3,
        4,
        4,
        3,
        3,
        4,
        1,
        3,
        2,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        3,
        4,
        4,
        3,
        2,
        4,
        2,
        4,
        4,
        3,
        4,
        4,
        4,
        4,
        3,
        4,
        4,
        1,
        4,
        1,
        4,
        2,
        4,
        3,
        4,
        4,
        4,
        3,
        2,
        3,
        2,
        3,
        4,
        4,
        3,
        4,
        4,
        2,
        4,
        4,
        2,
        4,
        3,
        4,
        4,
        4,
        4,
        3,
        4,
        3,
        3,
        4,
        2,
        3,
        4,
        3,
        4,
        3,
        4,
        4,
        1,
        4,
        2,
        2,
        4,
        4,
        1,
        2,
        4,
        2,
        3,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        4,
        4,
        4,
        2,
        3,
        4,
        1,
        4,
        1,
        1,
        2,
        2,
        4,
        4,
        3,
        1,
        4,
        3,
        4,
        4,
        4,
        1,
        2,
        4,
        4,
        3,
        2,
        4,
        4,
        2,
        4,
        4,
        4,
        2,
        2,
        4,
        4,
        3,
        2,
        4,
        3,
        4,
        4,
        4,
        2,
        3,
        2,
        4,
        4,
        2,
        3,
        3,
        4,
        3,
        2,
        2,
        4,
        2,
        3,
        3,
        3,
        3,
        4,
        3,
        3,
        4,
        3,
        4,
        4,
        4,
        4,
        4,
        1,
        3,
        3,
        2,
        1,
        4,
        4,
        1,
        4,
        2,
        3,
        4,
        2,
        4,
        4,
        3,
        4,
        3,
        4,
        2,
        3,
        4,
        4,
        4,
        3,
        1,
        4,
        3,
        4,
        4,
        3,
        3,
        3,
        2,
        4,
        4,
        4,
        2,
        3,
        4,
        3,
        4,
        4,
        1,
        4,
        4,
        3,
        2,
        4,
        1,
        4,
        3,
        1,
        4,
        4,
        3,
        4,
        4,
        4,
        2,
        4,
        4,
        4,
        1,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        4,
        2,
        4,
        4,
        3,
        4,
        4,
        4,
        2,
        4,
        3,
        3,
        3,
        4,
        4,
        3,
        3,
        3,
        4,
        4,
        2,
        4,
        4,
        3,
        3,
        4,
        4,
        4,
        2,
        1,
        3,
        2,
        4,
        4,
        2,
        3,
        3,
        4,
        4,
        2,
        3,
        3,
        3,
        4,
        4,
        4,
        2,
        3,
        4,
        1,
        4,
        4,
        3,
        3,
        4,
        4,
        4,
        4,
        4,
        4,
        2,
        3,
        4,
        1,
        4,
        4,
        3,
        3,
        4,
        2,
        4,
        4,
        2,
        3,
        3,
        3,
        2,
        4,
        4,
        3,
        4,
        3,
        4,
        3,
        4,
        1,
        3,
        4,
        2,
        4,
        4,
        3,
        3,
        4,
        2,
        4,
        3,
        2,
        3,
        3,
        4,
        2,
        4,
        4,
        4,
        4,
        4,
        4,
        4,
        3,
        4,
        4,
        4,
        3,
        3,
        4,
        4,
        4,
        2,
        2,
        4,
        3,
        4,
        4,
        4,
        2,
        4,
        2,
        4,
        3,
        4,
        4,
        4,
        4,
        4,
        3,
        4,
        4,
        2,
        4,
        3,
        4,
        4,
        4,
        4,
        1,
        4,
        3,
        4,
        4,
        4,
        3,
        3,
        3,
        3,
        2,
        4,
        4,
        2,
        3,
        2,
        3,
        3,
        3,
        4,
        2,
        4,
        4,
        4,
        1,
        3,
        2,
        4,
        4,
        2,
        3,
        4,
        4,
        3,
        3,
        2,
        4,
        3,
        4,
        4,
        3,
        4,
        3,
        3,
        4,
        4,
        2,
        4,
        4,
        4,
        4,
        4,
        2,
        3,
        4,
        4,
        2,
        2,
        3,
        2,
        3,
        4,
        1,
        4,
        4,
        2,
        2,
        4,
        4,
        4,
        4,
        3,
        4,
        2,
        2,
        4,
        4,
        4,
        2,
        2,
        4,
        4,
        4,
        1,
        4,
        4,
        1,
        4,
        4,
        4,
        3,
        3,
        2,
        4,
        3,
        2,
        3,
        1,
        4,
        4,
        4,
        4
    ];

    function rarity(uint256 tokenId) public view returns (uint256) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        return _rarity[tokenId - 1];
    }

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165, IERC165) returns (bool) {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    function totalSupply() public view virtual returns (uint256) {
        return _maxSupply - _numAvailableTokens;
    }

    function maxSupply() public view virtual returns (uint256) {
        return _maxSupply;
    }

    function balanceOf(
        address owner
    ) public view virtual override returns (uint256) {
        require(
            owner != address(0),
            "ERC721: balance query for the zero address"
        );
        return _balances[owner];
    }

    function ownerOf(
        uint256 tokenId
    ) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(
            owner != address(0),
            "ERC721: owner query for nonexistent token"
        );
        return owner;
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
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory baseURIMem = _baseURI();
        return
            string(abi.encodePacked(baseURIMem, (tokenId).toString(), ".json"));
    }

    function baseURI() public view virtual returns (string memory) {
        return _baseURI();
    }

    function _baseURI() internal view virtual returns (string memory) {
        return BASE_URI;
    }

    function approve(address to, uint256 tokenId) public virtual override {
        address owner = PixelShibellasERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    function getApproved(
        uint256 tokenId
    ) public view virtual override returns (address) {
        require(
            _exists(tokenId),
            "ERC721: approved query for nonexistent token"
        );

        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(
        address operator,
        bool approved
    ) public virtual override {
        _setApprovalForAll(_msgSender(), operator, approved);
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
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );

        _transfer(from, to, tokenId);
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
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        _safeTransfer(from, to, tokenId, _data);
    }

    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function _isApprovedOrOwner(
        address spender,
        uint256 tokenId
    ) internal view virtual returns (bool) {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner = PixelShibellasERC721.ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    function _mintIdWithoutBalanceUpdate(address to, uint256 tokenId) private {
        _beforeTokenTransfer(address(0), to, tokenId);

        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);

        _afterTokenTransfer(address(0), to, tokenId);
    }

    function mintPixelShibellas(uint _numToMint) public payable {
        require(
            _balances[msg.sender] + _numToMint <= MAX_MINT,
            "PixelShibellasERC721: minting more tokens than allowed"
        );
        require(
            msg.value >= MINT_PRICE * _numToMint,
            "PixelShibellasERC721: not enough BNB sent to mint"
        );

        _mintRandom(msg.sender, _numToMint);
    }

    function _mintRandom(address to, uint _numToMint) internal virtual {
        require(_msgSender() == tx.origin, "Contracts cannot mint");
        require(to != address(0), "ERC721: mint to the zero address");
        require(
            _numToMint > 0,
            "PixelShibellasERC721: need to mint at least one token"
        );

        // TODO: Probably don't need this as it will underflow and revert automatically in this case
        require(
            _numAvailableTokens >= _numToMint,
            "PixelShibellasERC721: minting more tokens than available"
        );

        uint updatedNumAvailableTokens = _numAvailableTokens;
        for (uint256 i; i < _numToMint; ++i) {
            // Do this ++ unchecked?
            uint256 tokenId = _getRandomAvailableTokenId(
                to,
                updatedNumAvailableTokens
            );

            _mintIdWithoutBalanceUpdate(to, tokenId + 1);

            --updatedNumAvailableTokens;
        }

        _numAvailableTokens = updatedNumAvailableTokens;
        _balances[to] += _numToMint;
    }

    function _getRandomAvailableTokenId(
        address to,
        uint updatedNumAvailableTokens
    ) internal returns (uint256) {
        uint256 randomNum = uint256(
            keccak256(
                abi.encode(
                    to,
                    tx.gasprice,
                    block.number,
                    block.timestamp,
                    block.difficulty,
                    blockhash(block.number - 1),
                    address(this),
                    updatedNumAvailableTokens
                )
            )
        );
        uint256 randomIndex = randomNum % updatedNumAvailableTokens;
        return
            _getAvailableTokenAtIndex(randomIndex, updatedNumAvailableTokens);
    }

    function _getAvailableTokenAtIndex(
        uint256 indexToUse,
        uint updatedNumAvailableTokens
    ) internal returns (uint256) {
        uint256 valAtIndex = _availableTokens[indexToUse];
        uint256 result;
        if (valAtIndex == 0) {
            // This means the index itself is still an available token
            result = indexToUse;
        } else {
            // This means the index itself is not an available token, but the val at that index is.
            result = valAtIndex;
        }

        uint256 lastIndex = updatedNumAvailableTokens - 1;
        uint256 lastValInArray = _availableTokens[lastIndex];
        if (indexToUse != lastIndex) {
            // Replace the value at indexToUse, now that it's been used.
            // Replace it with the data from the last index in the array, since we are going to decrease the array size afterwards.
            if (lastValInArray == 0) {
                // This means the index itself is still an available token
                _availableTokens[indexToUse] = lastIndex;
            } else {
                // This means the index itself is not an available token, but the val at that index is.
                _availableTokens[indexToUse] = lastValInArray;
            }
        }
        if (lastValInArray != 0) {
            // Gas refund courtsey of @dievardump
            delete _availableTokens[lastIndex];
        }

        return result;
    }

    function teamMint(address to, uint256 tokenId) public onlyOwner {
        _mintAtIndex(to, tokenId);
    }

    // Not as good as minting a specific tokenId, but will behave the same at the start
    // allowing you to explicitly mint some tokens at launch.
    function _mintAtIndex(address to, uint index) internal virtual {
        require(_msgSender() == tx.origin, "Contracts cannot mint");
        require(to != address(0), "ERC721: mint to the zero address");
        require(
            _numAvailableTokens >= 1,
            "PixelShibellasERC721: minting more tokens than available"
        );

        uint tokenId = _getAvailableTokenAtIndex(index, _numAvailableTokens);
        --_numAvailableTokens;

        _mintIdWithoutBalanceUpdate(to, tokenId);

        _balances[to] += 1;
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(
            PixelShibellasERC721.ownerOf(tokenId) == from,
            "ERC721: transfer from incorrect owner"
        );
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

    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(PixelShibellasERC721.ownerOf(tokenId), to, tokenId);
    }

    function _setApprovalForAll(
        address owner,
        address operator,
        bool approved
    ) internal virtual {
        require(owner != operator, "ERC721: approve to caller");
        _operatorApprovals[owner][operator] = approved;
        emit ApprovalForAll(owner, operator, approved);
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
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
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
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

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    function withdraw() public onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }
}