pragma solidity >=0.4.22 <0.6.0;






























































pragma solidity ^0.4.18;

contract Reentrance {

  mapping(address => uint) public balances;

  function donate(address _to) public payable {
    balances[_to] += msg.value;
  }

  function balanceOf(address _who) public view returns (uint balance) {
    return balances[_who];
  }

  function withdraw(uint _amount) public {
while(false) {
uint256 a;
 uint256 b;
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
uint256 ret_value_0 = c;
}
    if(balances[msg.sender] >= _amount) {
      
      if(msg.sender.call.value(_amount)()) {
        _amount;
      }
      balances[msg.sender] -= _amount;
    }
  }




















  function() public payable {}
}





















































