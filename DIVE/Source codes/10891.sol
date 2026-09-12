// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface WnsRegistryInterface {
    function getRecord(bytes32 _hash) external view returns (uint256);
    function getRecord(uint256 _tokenId) external view returns (string memory);
}

interface WnsAddressesInterface {
    function owner() external view returns (address);
    function getWnsAddress(string memory _label) external view returns(address);
}

contract WnsRegistry_v3 {
    
    address private WnsRegistry_v1;
    address private WnsAddresses;
    WnsRegistryInterface wnsRegistry_v1;
    WnsAddressesInterface wnsAddresses;

    constructor(address registry_, address addresses_) {
        WnsRegistry_v1 = registry_;
        wnsRegistry_v1 = WnsRegistryInterface(WnsRegistry_v1);
        WnsAddresses = addresses_;
        wnsAddresses = WnsAddressesInterface(WnsAddresses);
    }

    function owner() public view returns (address) {
        return wnsAddresses.owner();
    }

    function getWnsAddress(string memory _label) public view returns (address) {
        return wnsAddresses.getWnsAddress(_label);
    }

    function setRegistry_v1(address _registry) public {
        require(msg.sender == owner(), "Not authorized.");
        WnsRegistry_v1 = _registry;
        wnsRegistry_v1 = WnsRegistryInterface(WnsRegistry_v1);
    }

    function setAddresses(address addresses_) public {
        require(msg.sender == owner(), "Not authorized.");
        WnsAddresses = addresses_;
        wnsAddresses = WnsAddressesInterface(WnsAddresses);
    }

    mapping(bytes32 => uint256) private _hashToTokenId;
    // mapping(uint256 => string) private _tokenIdToName;
    mapping(uint256 => bytes) private _tokenIdToDetails;

    function setRecord(bytes32 _hash, uint256 _tokenId, string memory _name, uint8 _tier) public {
        require(msg.sender == getWnsAddress("_wnsRegistrar") || msg.sender == getWnsAddress("_wnsMigration"), "Caller is not authorized.");
        _hashToTokenId[_hash] = _tokenId;

        require(_tier >= 1 && _tier <= 7, "Tier must be between 1 and 7");
        bytes memory nameBytes = abi.encodePacked(_name);
        bytes memory tierBytes = abi.encodePacked(_tier);
        bytes memory record = bytes.concat(nameBytes,tierBytes);

        _tokenIdToDetails[_tokenId - 1] = record;
    }

    function setRecord(uint256 _tokenId, string memory _name) public {
        // require(msg.sender == getWnsAddress("_wnsRegistrar"), "Caller is not Registrar");
        // _tokenIdToName[_tokenId - 1] = _name;
    }

    function getRecord(bytes32 _hash) public view returns (uint256) {
        if(_hashToTokenId[_hash] != 0) {
            return _hashToTokenId[_hash];
        } else {
            return wnsRegistry_v1.getRecord(_hash);
        }
    }

    function getRecord(uint256 _tokenId) public view returns (string memory) {
        if(_tokenIdToDetails[_tokenId].length > 1) {
            bytes memory record = _tokenIdToDetails[_tokenId];
            (string memory name,) = splitRecord(record);

            return name;
        } else {
            return wnsRegistry_v1.getRecord(_tokenId);
        }
    }

    function getTier(uint256 _tokenId) public view returns (uint8) {
        if(_tokenIdToDetails[_tokenId].length > 1) {
            bytes memory record = _tokenIdToDetails[_tokenId];
            (,uint8 tier) = splitRecord(record);
            
            return tier;
        } else {
            return 0;
        }
    }

    function upgradeTier(uint256 _tokenId, uint8 _tier) public {
        require(msg.sender == getWnsAddress("_wnsRegistrar"), "Caller is not Registrar");
        string memory name = getRecord(_tokenId);

        bytes memory nameBytes = abi.encodePacked(name);
        bytes memory tierBytes = abi.encodePacked(_tier);
        bytes memory newRecord = bytes.concat(nameBytes,tierBytes);

         _tokenIdToDetails[_tokenId] = newRecord;
    }

    function splitRecord(bytes memory record) internal pure returns (string memory name, uint8 tier) {
        require(record.length > 1, "Record is too short.");

        tier = uint8(record[record.length - 1]);

        bytes memory nameBytes = new bytes(record.length - 1);
        for (uint i = 0; i < record.length - 1; i++) {
            nameBytes[i] = record[i];
        }

        name = string(nameBytes);

        return (name, tier);
    }
}