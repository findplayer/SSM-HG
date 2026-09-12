// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract GambitLotteryDailyBundle {
    address payable public manager;
    address payable[] public players;
    address public nativeToken;
    address public deadAddress=0x000000000000000000000000000000000000dEaD;
    address public lotteryWinner;
    address public usdtAddress=0xdAC17F958D2ee523a2206206994597C13D831ec7;

    mapping(address => uint256) public ownedTickets;

    uint256 public maxTicket=10;
    uint256 public round=1;
    uint256 public countDownTicker=86400; //1 Day
    uint256 public endTime=0;
    uint256 public ticketPrice = 400000000000000000000000; //400000 GAMBIT

    event Deposit(address indexed sender, uint256 amount);
    event Withdraw(address indexed recipient, uint256 amount);
    constructor(address nativeTokenAddress) {
        manager = payable(msg.sender);
        nativeToken = nativeTokenAddress;
    }
    IERC20 token = IERC20(nativeToken);
    IERC20 reward = IERC20(usdtAddress);

    function enter() public {
        require(ownedTickets[msg.sender] <= maxTicket-1, "Maximum Tickets is 10");
        require(block.timestamp <= endTime, "This Round is end !");

        token.transferFrom(msg.sender, deadAddress, ticketPrice);
        ownedTickets[msg.sender] += 1;
        players.push(payable(msg.sender));
    }

    function enterBundle() public {
        require(ownedTickets[msg.sender] <= maxTicket-1, "Maximum Tickets is 10");
        require(block.timestamp <= endTime, "This Round is end !");

        uint256 amount = maxTicket-ownedTickets[msg.sender];
        token.transferFrom(msg.sender, deadAddress, ticketPrice*amount);
        ownedTickets[msg.sender] += 1*amount;
        for (uint i = 0; i<amount; i++){
        players.push(payable(msg.sender));
        }
    }

    function random() private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, players)));
    }

    function pickWinner() public restricted {
        require(players.length > 0, "No players in the lottery");
        require(address(this).balance > 0, "Insufficient Balance");

        if (block.timestamp >= endTime) {
            uint index = random() % players.length;
            address payable winner = players[index];
            lotteryWinner = winner;
            reward.transfer(winner, reward.balanceOf(address(this)));

            // Reset players array for the next lottery
            for (uint256 i = 0; i < players.length; i++) {
                address ticketHolders = players[i];
                ownedTickets[ticketHolders] = 0;
            }

            players = new address payable[](0);
            round++;
            endTime=block.timestamp+countDownTicker;
        }
        else {
            require(false, "Countdown Condition Not Met");
        }
    }

    modifier restricted() {
        require(msg.sender == manager, "Only the manager can call this function");
        _;
    }

    function getPlayers() public view returns (address payable[] memory) {
        return players;
    }

    function getManager() public view returns (address) {
        return manager;
    }

    function getWinner() public view returns (address) {
        return lotteryWinner;
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function transferStuckToken(address addy, uint256 amount) public restricted {
        IERC20 stuckToken = IERC20(addy);

        stuckToken.transfer(msg.sender, amount);
    }

    function setTicketPrice(uint256 newPrice) public restricted {
        ticketPrice = newPrice;
    }

    function activateRound() public restricted {
        token = IERC20(nativeToken);
        endTime = block.timestamp + countDownTicker;
    }

    function setNativeTokenAddress(address _nativeToken) public restricted {
        nativeToken = _nativeToken;
        token = IERC20(nativeToken);
    }

    function getNativeTokenAddress() public view returns(IERC20) {
        return token;
    }

    function getTicketAmount(address sender) public view returns (uint) {
        return ownedTickets[sender];
    }
    
    function timeLeft() public view returns (uint256) {
        if (block.timestamp >= endTime) {
            return 0;
        } else {
            return endTime - block.timestamp;
        }
    }

    function getTotalTicketSold() public view returns (uint) {
        uint sold = 0;
        for (uint i = 0; i<players.length; i++){
            sold++;
        }
        return sold;
    }

    function setCountDown(uint256 newCountDown) public restricted {
        countDownTicker = newCountDown;
    }

    function startCountDown() public restricted {
        endTime = block.timestamp+countDownTicker;
    }

    function endRound() public restricted {
        endTime = 0;
    }

    function clearStuckETH() public restricted {
        manager.transfer(address(this).balance);
    }

    receive() external payable {}

    function getNativeTokenBalance() public view returns(uint256){
        return token.balanceOf(address(this));
    }

    function totalBurn() public view returns(uint256) {
        return token.balanceOf(deadAddress);
    }

    function getMaxTicket() public view returns(uint256) {
        return maxTicket;
    }

    function changeMaxTicket(uint256 newMaxTicket) public restricted{
        maxTicket = newMaxTicket;
    }

    function resetRound() public restricted {
        round = 1;
    }

    function changeReward(address newRewardAddress) public restricted {
        reward = IERC20(newRewardAddress);
    }
}