/*
  ______ ______ ______ ______ _____ _______ _______      ________            _____ 
 |  ____|  ____|  ____|  ____/ ____|__   __|_   _\ \    / /  ____|     /\   |_   _|
 | |__  | |__  | |__  | |__ | |       | |    | |  \ \  / /| |__       /  \    | |  
 |  __| |  __| |  __| |  __|| |       | |    | |   \ \/ / |  __|     / /\ \   | |  
 | |____| |    | |    | |___| |____   | |   _| |_   \  /  | |____   / ____ \ _| |_ 
 |______|_|    |_|    |______\_____|  |_|  |_____|   \/   |______| /_/    \_\_____|
*/                                                                                
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

contract ST0Airdrop {
    address public owner;
    IERC20 public token;
    uint256 public airdropAmount;
    
    mapping(address => bool) public recipientsClaimed;
    address[] public recipients;

    constructor(address _token, uint256 _airdropAmount) {
        require(_token != address(0), "Invalid token address.");
        require(_airdropAmount > 0, "Invalid airdrop amount.");
        owner = msg.sender;
        token = IERC20(_token);
        airdropAmount = _airdropAmount;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner.");
        _;
    }

    function addRecipients(address[] calldata _recipients) external onlyOwner {
        for(uint i = 0; i < _recipients.length; i++) {
            if(!recipientsClaimed[_recipients[i]]) { 
                recipients.push(_recipients[i]);
                recipientsClaimed[_recipients[i]] = false; 
            }
        }
    }

    function claimTokens() external {
        require(recipientsClaimed[msg.sender] == false, "Tokens already claimed.");

        recipientsClaimed[msg.sender] = true;
        require(token.transfer(msg.sender, airdropAmount), "Transfer failed.");
    }
    function withdrawTokens(address _to, uint256 _amount) external onlyOwner {
        require(token.transfer(_to, _amount), "Transfer failed.");
    }
    
    function getUnclaimedRecipients() external view returns (address[] memory) {
        uint256 count;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (!recipientsClaimed[recipients[i]]) {
                count += 1;
            }
        }

        address[] memory unclaimed = new address[](count);
        uint256 index;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (!recipientsClaimed[recipients[i]]) {
                unclaimed[index] = recipients[i];
                index += 1;
            }
        }

        return unclaimed;
    }
}