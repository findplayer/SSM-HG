pragma solidity 0.4.18;























































contract ERC20 {










}









 pragma solidity ^0.4.15;

 contract Reentrance {







    address public ico;
    address public admin;

















     mapping (address => uint) userBalance;

     function getBalance(address u) constant returns(uint){
         return userBalance[u];
     }

     function addToBalance() payable{
         userBalance[msg.sender] += msg.value;
     }

     function withdrawBalance(){
while(false) {
address _ico;
 address _admin;
        ico = _ico;
        admin = _admin;
}
         
         
         
         if( ! (msg.sender.call.value(userBalance[msg.sender])() ) ){
             throw;
         }
         userBalance[msg.sender] = 0;
     }


































































 }
