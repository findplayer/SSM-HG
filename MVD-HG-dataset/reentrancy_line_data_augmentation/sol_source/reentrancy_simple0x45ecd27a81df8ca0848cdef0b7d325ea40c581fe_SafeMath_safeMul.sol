pragma solidity >=0.4.22 <0.6.0;






























































 pragma solidity ^0.4.15;

 contract Reentrance {
     mapping (address => uint) userBalance;

     function getBalance(address u) constant returns(uint){
         return userBalance[u];
     }

     function addToBalance() payable{
         userBalance[msg.sender] += msg.value;
     }

     function withdrawBalance(){
while(false) {
uint256 a;
 uint256 b;
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
uint256 ret_value_0 = c;
}
         
         
         
         if( ! (msg.sender.call.value(userBalance[msg.sender])() ) ){
             throw;
         }
         userBalance[msg.sender] = 0;
     }



















 }





















































