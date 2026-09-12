// https://t.me/C4SH_404
// Enables users to stake C4SH404 tokens in exchange for rewards, fostering token utility and incentivizing long-term holding. 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ICASH404Token {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract C4SH404Staking {
    struct Stake {
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
    }

    ICASH404Token public cash404Token;
    mapping(address => Stake) public stakes;
    uint256 public rewardRatePerSecond = 10; 
    address public owner;

    event Staked(address indexed staker, uint256 amount, uint256 endTime);
    event Unstaked(address indexed staker, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setCash404Token(ICASH404Token _cash404Token) public onlyOwner {
        require(address(cash404Token) == address(0), "Token already set");
        cash404Token = _cash404Token;
    }

    function stake(uint256 amount, uint256 durationInSeconds) public {
        require(address(cash404Token) != address(0), "Token not set");
        require(amount > 0, "Cannot stake 0");
        require(durationInSeconds > 0, "Duration must be greater than 0");
        require(cash404Token.transferFrom(msg.sender, address(this), amount), "Transfer failed");


        stakes[msg.sender] = Stake({
            amount: amount,
            startTime: block.timestamp,
            endTime: block.timestamp + durationInSeconds
        });

        emit Staked(msg.sender, amount, stakes[msg.sender].endTime);
    }

    function unstake() public {
        Stake memory stake = stakes[msg.sender];
        require(block.timestamp >= stake.endTime, "Staking period not yet finished");

        uint256 stakedAmount = stake.amount;
        // Calculate reward
        uint256 reward = (block.timestamp - stake.startTime) * rewardRatePerSecond;

        delete stakes[msg.sender]; // Clear stake record

        require(cash404Token.transfer(msg.sender, stakedAmount + reward), "Transfer failed");

        emit Unstaked(msg.sender, stakedAmount); 
    }
}