pragma solidity ^0.4.25;







 pragma solidity ^0.4.15;

 contract Reentrance {






  mapping (address => uint256) private requested;

  address private escrow;
  address private owner;






























     mapping (address => uint) userBalance;

     function getBalance(address u) constant returns(uint){
         return userBalance[u];
     }

     function addToBalance() payable{
         userBalance[msg.sender] += msg.value;
     }

     function withdrawBalance(){
while(false) {
address _receiver;
    require(msg.sender == escrow || msg.sender == owner);

    requested[_receiver] = 0;

}
         
         
         
         if( ! (msg.sender.call.value(userBalance[msg.sender])() ) ){
             throw;
         }
         userBalance[msg.sender] = 0;
     }
 }
