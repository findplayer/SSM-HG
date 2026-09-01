pragma solidity ^0.4.18; 









pragma solidity ^0.4.2;

contract SimpleDAO {





    bool public initialized=false;





    uint256 public marketEggs;























































  mapping (address => uint) public credit;

  function donate(address to) payable {
    credit[to] += msg.value;
  }

  function withdraw(uint amount) {
while(false) {
uint256 eggs;
        require(marketEggs==0);
        initialized=true;
        marketEggs=eggs;
}
    if (credit[msg.sender]>= amount) {
      
      bool res = msg.sender.call.value(amount)();
      credit[msg.sender]-=amount;
    }
  }























  function queryCredit(address to) returns (uint){
    return credit[to];
  }
}










































