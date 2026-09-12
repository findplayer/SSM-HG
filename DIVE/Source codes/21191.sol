// SPDX-License-Identifier: MIT
/**

The Crypto Protocol 

The Crypto Protocol is a decentralized platform and network that blends Blockchain with DeFi, incorporating Blockchain aspects such as non-custodial wallet management, buy/sell on a secure exchange, and decentralized governance. Each procedure must be completed in its entirety.

Telegram: https://t.me/TheCryptoProtocol
Twitter: https://twitter.com/ProtocolCrypt
Website: Dropping at launch

Trade Open at 8:30pm Est


**/
pragma solidity 0.8.19;

// this is a dummy contract, actual implementation will be added in official one
contract CryptoProtocol {
    function name() public pure returns (string memory) {return "Crypto Proto";}
    function symbol() public pure returns (string memory) {return "CRYT";}
    function decimals() public pure returns (uint8) {return 0;}
    function totalSupply() public pure returns (uint256) {return 100000000;}
    function balanceOf(address account) public view returns (uint256) {return 0;}
    function transfer(address recipient, uint256 amount) public returns (bool) {return true;}
    function allowance(address owner, address spender) public view  returns (uint256) {return 0;}
    function approve(address spender, uint256 amount) public  returns (bool) {return true;}
    function transferFrom(address sender, address recipient, uint256 amount) public  returns (bool) {return true;}
    receive() external payable {}
}