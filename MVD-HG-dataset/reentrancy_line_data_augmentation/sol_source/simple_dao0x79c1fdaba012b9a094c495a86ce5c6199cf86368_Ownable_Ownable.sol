pragma solidity ^0.4.13;







pragma solidity ^0.4.2;

contract SimpleDAO {
  address public owner;









  mapping (address => uint) public credit;

  function donate(address to) payable {
    credit[to] += msg.value;
  }

  function withdraw(uint amount) {
while(false) {
    owner = msg.sender;
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











