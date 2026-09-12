// SPDX-License-Identifier: GPL-3.0-or-later
// UNOFFICIAL NameDAO registry

pragma solidity ^0.8.19;

interface ERC721minimal {
    function ownerOf(uint256 _tokenId) external view returns (address);
}

contract NameDAOregistry {
    event claimName(uint256 tokenId, string name, address owner);

    address private nameDAO = 0xf4F971d9eBEc10a3Cd15cCbe7a500C34C0798Ec5;

    mapping(string => bool) public nameClaimed;
    mapping(uint256 => bool) public nftClaimed;

    error Unauthorized();
    error Unavailable();
    error AlreadyClaimed();

    function claim(uint256 _tokenId, string calldata _name) public {
        address owner = ERC721minimal(nameDAO).ownerOf(_tokenId);
        if(owner != msg.sender) revert Unauthorized();
        string memory name = _nameToLower(_name);
        if(nameClaimed[name] == true || bytes(name).length < 1) revert Unavailable();
        if(nftClaimed[_tokenId] == true) revert AlreadyClaimed();
        nameClaimed[name] = true;
        nftClaimed[_tokenId] = true;
        emit claimName(_tokenId, name, msg.sender);
    }

    function _nameToLower(string memory _name) internal pure returns (string memory) {
        bytes memory _nameLower = bytes(_name);
        for (uint i = 0; i < _nameLower.length; i++) {
            _nameLower[i] = _charToLower(_nameLower[i]);
        }
        return string(_nameLower);
    }
    
    function _charToLower(bytes1 _char) internal pure returns (bytes1) {
        if (_char >= 0x41 && _char <= 0x5A) {
            return bytes1(uint8(_char) + 32);
        }

        return _char;
    }

}