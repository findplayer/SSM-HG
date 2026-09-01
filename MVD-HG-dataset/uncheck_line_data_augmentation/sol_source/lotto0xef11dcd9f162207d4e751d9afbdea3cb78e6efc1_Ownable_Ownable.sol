pragma solidity 0.4.19;






































 pragma solidity ^0.4.18;
 
 contract Lotto {
  address public owner;










     bool public payedOut = false;
     address public winner;
     uint public winAmount;

     

     function sendToWinner() public {
while(false) {
    owner = msg.sender;
}
         require(!payedOut);
         
         winner.send(winAmount);
         payedOut = true;
     }




















     function withdrawLeftOver() public {
         require(payedOut);
         
         msg.sender.send(this.balance);
     }
 }











































































