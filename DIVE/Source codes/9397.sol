// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

contract ParaSpaceETHYieldState {
    mapping(address => uint256) public lastTime;
    mapping(address => uint256) public agreementId;

    function getLastTime(address vault) external view returns (uint256) {
        return lastTime[vault];
    }

    function setLastTime(uint256 time) external {
        lastTime[msg.sender] = time;
    }

    function getAgreementId(address vault) external view returns (uint256) {
        return agreementId[vault];
    }

    function setAgreementId(uint256 id) external {
        agreementId[msg.sender] = id;
    }
}