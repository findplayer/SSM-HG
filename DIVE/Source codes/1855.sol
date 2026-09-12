// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

interface URIContract {
  function tokenURI(uint256 tokenId) external view returns (string memory);
}

contract TokenArtURI {
  using Strings for uint256;

  string externalUrl = 'https://tokenart.nyc';
  string description;

  Project[3] public projects;

  struct Project {
    string imageURI;
    string artistName;
    string license;
    address forwardURIContract;
    address projectOwner;
  }

  constructor () {
    string memory _license = 'CC BY-NC 2.0';
    string memory _imageURI = 'ipfs://bafybeigbaq5ldqonkysn47cg2e2njjunacudoxiqkcl32pcarm5wfhhfey/';

    projects[0].artistName = 'Emily Edelman';
    projects[0].license = _license;
    projects[0].imageURI = _imageURI;
    projects[0].projectOwner = msg.sender;

    projects[1].artistName = 'Alex Supkay';
    projects[1].license = _license;
    projects[1].imageURI = _imageURI;
    projects[1].projectOwner = msg.sender;

    projects[2].artistName = 'Steve Pikelny';
    projects[2].license = _license;
    projects[2].imageURI = _imageURI;
    projects[2].projectOwner = msg.sender;
  }

  function tokenURI(uint256 tokenId) external view returns (string memory) {
    Project memory project;
    if (tokenId < 100) {
      project = projects[0];
    } else if (tokenId < 200) {
      project = projects[1];
    } else {
      project = projects[2];
    }

    if (project.forwardURIContract != address(0)) {
      return URIContract(project.forwardURIContract).tokenURI(tokenId);
    }

    bytes memory json = abi.encodePacked(
      'data:application/json;utf8,',
      '{"name": "Token Art Art Token #', tokenId.toString(),'",'
      '"license": "', project.license, '",'
      '"description": "', description, '",'
      '"external_url": "', externalUrl, '",'
      '"attributes": [{"trait_type": "Artist", "value": "', project.artistName, '"}],'
      '"image": "', project.imageURI, tokenId.toString(), '.png',
      '"}'
    );
    return string(json);
  }

  receive() external payable {
    uint256 oneThird = msg.value / 3;

    payable(projects[0].projectOwner).transfer(oneThird);
    payable(projects[1].projectOwner).transfer(oneThird);
    payable(projects[2].projectOwner).transfer(oneThird);
  }

  modifier onlyArtist {
    require(
      msg.sender == projects[0].projectOwner
      || msg.sender == projects[1].projectOwner
      || msg.sender == projects[2].projectOwner,
      'Signer must be artist'
    );
    _;
  }

  function updateExternalUrl(string calldata newExternalUrl) external onlyArtist {
    externalUrl = newExternalUrl;
  }

  function updateDescription(string calldata newDescription) external onlyArtist {
    description = newDescription;
  }

  function updateProjectInfo(
    uint256 projectId,
    string memory imageURI,
    string memory artistName,
    string memory license
  ) external {
    require(msg.sender == projects[projectId].projectOwner, 'Only artist can update this project');
    projects[projectId].imageURI = imageURI;
    projects[projectId].artistName = artistName;
    projects[projectId].license = license;
  }

  function redirectProject(uint256 projectId, address forwardURIContract) external {
    require(msg.sender == projects[projectId].projectOwner, 'Only artist can update this project');
    projects[projectId].forwardURIContract = forwardURIContract;
  }

  function transferProjectOwnership(uint256 projectId, address projectOwner) external {
    require(msg.sender == projects[projectId].projectOwner, 'Only artist can update this project');
    projects[projectId].projectOwner = projectOwner;
  }
}





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

    /*
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