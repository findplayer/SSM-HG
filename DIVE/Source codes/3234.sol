// SPDX-License-Identifier: MIT


pragma solidity 0.8.7;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
}

contract TokenAirdrop {
    address public owner;
    address public airdropWallet;
    address public tokenAddress;

    constructor(address _airdropWallet, address _tokenAddress) {
        owner = msg.sender;
        airdropWallet = _airdropWallet;
        tokenAddress = _tokenAddress;
    }

    function setAirdropWallet(address _airdropWallet) public onlyOwner {
        airdropWallet = _airdropWallet;
    }

    function setTokenAddress(address _tokenAddress) public onlyOwner {
        tokenAddress = _tokenAddress;
    }


    function airdrop(address[] calldata participants, uint[] calldata tokens) public onlyOwner {
        require(airdropWallet != address(0), "Airdrop wallet address not set");
        require(tokenAddress != address(0), "Token address not set");
        require(participants.length == tokens.length,"Participants and token amounts mismatch");

        IERC20 token = IERC20(tokenAddress);

        uint sum = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            sum = sum+tokens[i];
        }
        require(token.allowance(airdropWallet,address(this))>=sum,"Insuffecient allowance");
        for (uint256 i = 0; i < participants.length; i++) {
            require(token.transferFrom(airdropWallet, participants[i], tokens[i]), "Transfer failed");
        }
    }

    function reset() public onlyOwner {
        airdropWallet = address(0);
        tokenAddress = address(0);  
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }
}