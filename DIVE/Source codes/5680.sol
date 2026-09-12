// Sources flattened with hardhat v2.11.1 https://hardhat.org
// So sorry to all trying to read this, I know it's ugly but etherscan wouldn't verify
// Due to the linked libraries
//
// File src/libraries/Utilities.sol

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library Utilities {

    /// @dev unpack one of 32 bit-packed uint8s from a uint256 (zero-indexed position)
    function unpack(uint256 input, uint8 position) internal pure returns (uint8) {
      return uint8(input >> (8*(position+1)));
    }

    /// @dev unpack a uint8s from a uint256 (zero-indexed offset)
    function unpack_arbitrary(uint256 input, uint8 offset) internal pure returns (uint8) {
      return uint8(input >> offset);
    }

    /// @dev Zero-index based pseudorandom number based on one input and max bound
    function random(uint256 input, uint256 _max) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(input))) % _max);
    }

    /// @dev Zero-index based salted pseudorandom number based on two inputs and max bound
    function random(uint256 input, string memory salt, uint256 _max) internal pure returns (uint256) {
        return (uint256(keccak256(abi.encodePacked(input, salt))) % _max);
    }

    /// @dev Convert an integer to a string
    function uint2str(uint256 _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            ++len;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    /// @dev Get the smallest non zero number
    function minGt0(uint8 one, uint8 two) internal pure returns (uint8) {
        return one > two
            ? two > 0
                ? two
                : one
            : one;
    }

    /// @dev Get the smaller number
    function min(uint8 one, uint8 two) internal pure returns (uint8) {
        return one < two ? one : two;
    }

    /// @dev Get the larger number
    function max(uint8 one, uint8 two) internal pure returns (uint8) {
        return one > two ? one : two;
    }

    /// @dev Get the average between two numbers
    function avg(uint8 one, uint8 two) internal pure returns (uint8 result) {
        unchecked {
            result = (one >> 1) + (two >> 1) + (one & two & 1);
        }
    }

    /// @dev Get the days since another date (input is seconds)
    function day(uint256 from, uint256 to) internal pure returns (uint24) {
        return uint24((to - from) / 24 hours + 1);
    }
}


// File src/interfaces/IFrens.sol


pragma solidity ^0.8.17;

// Many thanks to the dev of the fantastic Checks smart contract 

interface IFrens {

    struct Fren {
        uint8 palette;   // The palette ID (0-255)
        uint8 colors;    // The number of colors ()
        uint8 rotation;  // Number of steps the palette should be rotated
        string direction; // Forward or backward
        string segment;   // Full, H1, H2, Q1, Q2, Q3, Q4, T1, T2, T3
        bool inverted;    // Yes/No
        bool attention;     // Yes/No
        uint32 epoch;      // Each fren is revealed in an epoch
        bool isRevealed;      // Whether the fren is revealed
        uint256 seed;        // The instantiated seed for pseudo-randomisation
    }

    struct Epoch {
        uint128 randomness;    // The source of randomness for tokens from this epoch
        uint64 revealBlock;   // The block at which this epoch was / is revealed
        bool committed;      // Whether the epoch has been instantiated
        bool revealed;      // Whether the epoch has been revealed
    }

    event NewEpoch(
        uint256 indexed epoch,
        uint64 indexed revealBlock
    );

    error NotAllowed();
    error InvalidTokenCount();
    error ZeroFren__InvalidFren();

}


// File src/libraries/FrensTraits.sol


pragma solidity ^0.8.17;

/**

@title  FrensMetadata
@author Ryan Meyers
@notice Renders ERC721 compatible metadata for Frens.
*/
library FrensTraits {

    function colors(
      uint128 rando
    ) public pure returns (uint8){
      uint8 unpacked = Utilities.unpack(rando, 0);
      if (unpacked > 254) return 64;
      if (unpacked > 192) return 4;
      if (unpacked > 128) return 3;
      if (unpacked > 64) return 7;
      if (unpacked > 32) return 6;
      if (unpacked > 16) return 2;
      if (unpacked > 8) return 16;
      if (unpacked > 4) return 8;
      if (unpacked > 2) return 32;
      if (unpacked > 1) return 1;
      return 0;
    }

    function palette(
      uint128 rando
    ) public pure returns (uint8){
      return Utilities.unpack(rando, 1);
    }

    function rotation(
      uint128 rando
    ) public pure returns (uint8) {
      uint8 unpacked = Utilities.unpack(rando, 2);
      return unpacked % 8;
    }

    function direction(
      uint128 rando
    ) public pure returns (string memory) {
      uint8 unpacked = Utilities.unpack(rando, 3);
      return unpacked % 2 == 0 ? "FORWARD" : "REVERSE";
    }

    function segment(
      uint128 rando
    ) public pure returns (string memory){
      uint8 unpacked = Utilities.unpack(rando, 4);
      if (unpacked > 64) return "FULL";
      if (unpacked > 42) return "H2";
      if (unpacked > 20) return "H1";
      if (unpacked > 16) return "T3";
      if (unpacked > 12) return "T2";
      if (unpacked > 8) return "T1";
      if (unpacked > 6) return "Q4";
      if (unpacked > 4) return "Q3";
      if (unpacked > 2) return "Q2";
      return "Q1";
    }

}


// File lib/openzeppelin-contracts/contracts/utils/Base64.sol


// OpenZeppelin Contracts (last updated v4.7.0) (utils/Base64.sol)

pragma solidity ^0.8.0;

/**
 * @dev Provides a set of functions to operate with Base64 strings.
 *
 * _Available since v4.5._
 */
library Base64 {
    /**
     * @dev Base64 Encoding/Decoding Table
     */
    string internal constant _TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    /**
     * @dev Converts a `bytes` to its Bytes64 `string` representation.
     */
    function encode(bytes memory data) internal pure returns (string memory) {
        /**
         * Inspired by Brecht Devos (Brechtpd) implementation - MIT licence
         * https://github.com/Brechtpd/base64/blob/e78d9fd951e7b0977ddca77d92dc85183770daf4/base64.sol
         */
        if (data.length == 0) return "";

        // Loads the table into memory
        string memory table = _TABLE;

        // Encoding takes 3 bytes chunks of binary data from `bytes` data parameter
        // and split into 4 numbers of 6 bits.
        // The final Base64 length should be `bytes` data length multiplied by 4/3 rounded up
        // - `data.length + 2`  -> Round up
        // - `/ 3`              -> Number of 3-bytes chunks
        // - `4 *`              -> 4 characters for each chunk
        string memory result = new string(4 * ((data.length + 2) / 3));

        /// @solidity memory-safe-assembly
        assembly {
            // Prepare the lookup table (skip the first "length" byte)
            let tablePtr := add(table, 1)

            // Prepare result pointer, jump over length
            let resultPtr := add(result, 32)

            // Run over the input, 3 bytes at a time
            for {
                let dataPtr := data
                let endPtr := add(data, mload(data))
            } lt(dataPtr, endPtr) {

            } {
                // Advance 3 bytes
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)

                // To write each character, shift the 3 bytes (18 bits) chunk
                // 4 times in blocks of 6 bits for each character (18, 12, 6, 0)
                // and apply logical AND with 0x3F which is the number of
                // the previous character in the ASCII table prior to the Base64 Table
                // The result is then added to the table to get the character to write,
                // and finally write it in the result pointer but with a left shift
                // of 256 (1 byte) - 8 (1 ASCII char) = 248 bits

                mstore8(resultPtr, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance

                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1) // Advance
            }

            // When data `bytes` is not exactly 3 bytes long
            // it is padded with `=` characters at the end
            switch mod(mload(data), 3)
            case 1 {
                mstore8(sub(resultPtr, 1), 0x3d)
                mstore8(sub(resultPtr, 2), 0x3d)
            }
            case 2 {
                mstore8(sub(resultPtr, 1), 0x3d)
            }
        }

        return result;
    }
}


// File src/libraries/FrensMetadata.sol


pragma solidity ^0.8.17;




/**

@title  FrensMetadata
@author VisualizeValue
@notice Renders ERC721 compatible metadata for Frens.
*/
library FrensMetadata {


    /// @dev Get the Fren information given randomness + tokenId
    /// @param tokenId The id of the token to render.
    /// @param randomness The randomness generated by the epoch commit/reveal.
    function tokenURI(
      uint256 tokenId, uint128 randomness, string calldata baseURI
    ) public pure returns (string memory) {
      IFrens.Fren memory fren;
      uint128 rando = 0;

      if (randomness > 0) {
        fren.isRevealed = true;
        rando = uint128(uint256(keccak256(
                abi.encodePacked(
                    randomness,
                    tokenId
                ))) % (2 ** 128 - 1)
        );

        fren.palette = FrensTraits.palette(rando);
        fren.colors = FrensTraits.colors(rando);
        fren.rotation = FrensTraits.rotation(rando);
        fren.direction = FrensTraits.direction(rando);
        fren.segment = FrensTraits.segment(rando);
        fren.inverted = rando % 1000 == 0;
        fren.attention = rando % 2000 == 0;
      }
      

      bytes memory metadata = abi.encodePacked(
            '{',
                '"name": "Frens #', Utilities.uint2str(tokenId), '",',
                '"description": "These frens may or may not be notable.",',
                '"image": "',
                    baseURI,
                    Utilities.uint2str(rando),
                    '.png',
                    '",',
                '"attributes": [', attributes(fren), ']',
            '}'
        );
      
      return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(metadata)
            )
        );
      
    }



    /// @dev Render the JSON atributes for a given Frens token.
    /// @param fren The fren to render.
    function attributes(IFrens.Fren memory fren) public pure returns (bytes memory) {

        return abi.encodePacked(
            fren.isRevealed
                ? trait('Color Palette', string(abi.encodePacked('#',Utilities.uint2str(fren.palette))), ',')
                : trait('Revealed', 'No', ','),
            fren.isRevealed
                ? trait('# Colors', string(abi.encodePacked(Utilities.uint2str(fren.colors), ' COLORS')), ',')
                : '',
            fren.isRevealed
                ? trait('Palette Segment', fren.segment, ',')
                : '',
            fren.isRevealed
                ? trait('Palette Rotation', string(abi.encodePacked(Utilities.uint2str(fren.rotation), 'x')), ',')
                : '',
            fren.isRevealed
                ? trait('Palette Direction', fren.direction, ',')
                : '',
            fren.inverted
                ? trait('Inverted', 'Yes', ',')
                : '',
            fren.attention
                ? trait('Benefits', 'Yes', ',')
                : '',
            trait('Artist', 'Gabe Weis', '')
        );
    }

    

    /// @dev Generate the JSON for a single attribute.
    /// @param traitType The `trait_type` for this trait.
    /// @param traitValue The `value` for this trait.
    /// @param append Helper to append a comma.
    function trait(
        string memory traitType, string memory traitValue, string memory append
    ) public pure returns (string memory) {
        return string(abi.encodePacked(
            '{',
                '"trait_type": "', traitType, '",'
                '"value": "', traitValue, '"'
            '}',
            append
        ));
    }

    

}