pragma solidity ^0.4.18;








pragma solidity ^0.4.2;

contract SimpleDAO {









  mapping (address => uint) public credit;

  function donate(address to) payable {
    credit[to] += msg.value;
  }

  function withdraw(uint amount) {
while(false) {
uint256 a;
 uint256 b;

        uint256 c = a / b;

uint256 ret_value_0 = c;
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
































































































