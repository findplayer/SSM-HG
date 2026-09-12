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

contract ST0Rewards {
    address public owner;
    IERC20 public stage0Token;
    mapping(address => bool) public verifiers;

    event RewardDistributed(address indexed receiver, uint256 amount);

    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        owner = msg.sender;
        stage0Token = IERC20(_token);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can perform this action");
        _;
    }

    modifier onlyVerifier() {
        require(verifiers[msg.sender], "Only a designated verifier can perform this action");
        _;
    }

    function addVerifier(address _verifier) public onlyOwner {
        require(_verifier != address(0), "Invalid verifier address");
        verifiers[_verifier] = true;
    }

    function removeVerifier(address _verifier) public onlyOwner {
        require(verifiers[_verifier], "This address is not a designated verifier");
        verifiers[_verifier] = false;
    }


    function distributeReward(address _recipient, uint256 _amount) public onlyVerifier {
        require(_recipient != address(0), "Invalid recipient address");
        require(_amount > 0, "Invalid reward amount");

        emit RewardDistributed(_recipient, _amount);
    
        require(stage0Token.transfer(_recipient, _amount), "Token transfer failed");
    }
}