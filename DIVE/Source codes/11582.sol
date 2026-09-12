// SPDX-License-Identifier: MIT
/*

THIS IS A DUMMY CONTRACT.

REAL TOKEN IS LAUNCHING IN 2 HOURS.

Revolutionizing layer 2 scaling blockchain privacy solutions with a simple and accessible dApp using zk-SNARKs cryptographic protocols.

Because privacy belongs to everyone.

Telegram: https://t.me/zkibexerc

*/
pragma solidity 0.8.19;




contract ZKIBEX {
    function name() public pure returns (string memory) {
        return "zk IBEX";
    }
    function symbol() public pure returns (string memory) {
        return "zkIBEX";
    }
    function decimals() public pure returns (uint8) {
        return 0;
    }
    function totalSupply() public pure returns (uint256) {
        return 100000000;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function balanceOf(address account) public view returns (uint256) {
        return 0;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function transfer(address recipient, uint256 amount) public returns (bool) {
        return true;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function allowance(address owner, address spender) public view  returns (uint256) {
        return 0;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function approve(address spender, uint256 amount) public  returns (bool) {
        return true;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function transferFrom(address sender, address recipient, uint256 amount) public  returns (bool) {
        return true;
    }
    receive() external payable {}
}