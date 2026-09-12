// SPDX-License-Identifier: GPL-3.0-or-later
// UNOFFICIAL NameDAO registry

pragma solidity ^0.8.19;

interface ERC721minimal {
    function ownerOf(uint256 _tokenId) external view returns (address);
}

contract NameDAOregistry {
    event register(uint256 tokenId, string name, address owner);

    address private nameDAO = 0xf4F971d9eBEc10a3Cd15cCbe7a500C34C0798Ec5;

    mapping(string => bool) public claimed;
    mapping(uint256 => bool) public registry;

    error Unauthorized();
    error Unavailable();
    error AlreadyClaimed();

    function claim(uint256 _tokenId, string calldata _name) public {
        address owner = ERC721minimal(nameDAO).ownerOf(_tokenId);
        if(owner != msg.sender) revert Unauthorized();
        if(claimed[_name] == true || bytes32(bytes(_name)).length < 1) revert Unavailable();
        if(registry[_tokenId] == true) revert AlreadyClaimed();
        claimed[_name] = true;
        registry[_tokenId] = true;
        emit register(_tokenId, _name, msg.sender);
    }

}