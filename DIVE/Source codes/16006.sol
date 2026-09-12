// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.19;

interface ERC721minimal {
    function ownerOf(uint256 _tokenId) external view returns (address);
}

contract NameDAOregistry {
    event register(uint256 tokenId, bytes32 name, address owner);

    address private nameDAO = 0xf4F971d9eBEc10a3Cd15cCbe7a500C34C0798Ec5;

    mapping(bytes32 => bool) public claimed;
    mapping(uint256 => bytes32) public registry;

    error Unauthorized();
    error NameUnavailable();
    error UserAlreadyClaimedName();
    error InvalidName();

    function claimName(uint256 tokenId, bytes32 name) public {
        address owner = ERC721minimal(nameDAO).ownerOf(tokenId);
        if(owner != msg.sender) revert Unauthorized();
        if(claimed[name] == true) revert NameUnavailable();
        if(registry[tokenId].length >0) revert UserAlreadyClaimedName();
        if(name.length < 1) revert InvalidName();
        claimed[name] = true;
        registry[tokenId] = name;
        emit register(tokenId, name, msg.sender);
    }

}