pragma solidity 0.8.9;

// SPDX-License-Identifier: MIT
contract ParaSpaceYieldState {
    mapping(address => mapping(address => uint256)) public lastTime;
    mapping(address => uint256[]) public agreementIds;

    function getLastTime(address vault, address asset) external view returns (uint256) {
        return lastTime[vault][asset];
    }

    function setLastTime(address asset, uint256 time) external {
        lastTime[msg.sender][asset] = time;
    }

    function getAgreementIds(address vault) external view returns (uint256[] memory) {
        return agreementIds[vault];
    }

    function addAgreementId(uint256 id) external {
        agreementIds[msg.sender].push(id);
    }

    function getAgreementIdIndex(address vault, uint256 id) public view returns (uint256) {
        uint256[] memory ids = agreementIds[vault];
        uint256 length = ids.length;
        for (uint256 i = 0; i < length; i++) {
            if (ids[i] == id) {
                return i;
            }
        }
        return type(uint256).max;
    }

    function removeAgreementId(uint256 id) external {
        uint256 index = getAgreementIdIndex(msg.sender, id);
        uint256 length = agreementIds[msg.sender].length;
        require(index < length, "ParaSpaceYieldState: invalid id");
        agreementIds[msg.sender][index] = 0;
        bool remove = true;
        for (uint256 i = 0; i < length; i++) {
            if (agreementIds[msg.sender][i] != 0) {
                remove = false;
                break;
            }
        }
        if (remove) {
            delete agreementIds[msg.sender];
        }
    }
}