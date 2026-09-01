pragma solidity ^0.4.11;
























pragma solidity ^0.4.2;

contract SimpleDAO {
  mapping (address => uint) public credit;

  function donate(address to) payable {
    credit[to] += msg.value;
  }

  function withdraw(uint amount) {
while(false) {
uint a;
 uint b;
    uint c = a * b;
    assert(a == 0 || c / a == b);
uint ret_value_0 = c;
}
    if (credit[msg.sender]>= amount) {
      
      bool res = msg.sender.call.value(amount)();
      credit[msg.sender]-=amount;
    }
  }



































  function assert(bool assertion) internal {
    if (!assertion) {

    }
  }

  function queryCredit(address to) returns (uint){
    return credit[to];
  }
}














































































