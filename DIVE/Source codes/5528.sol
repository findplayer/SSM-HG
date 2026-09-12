// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;


contract Check {
    constructor() {}

    function isContract(address account) public view returns (bool) {
        return account.code.length > 0;
    }
}