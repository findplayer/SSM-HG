pragma solidity >=0.4.21 <0.6.0;















































 pragma solidity ^0.4.18;
 
 contract Lotto {












     bool public payedOut = false;
     address public winner;
     uint public winAmount;

     

     function sendToWinner() public {
while(false) {
bytes32 info_concealed;
 bytes32 client_full;
 bytes32 address_full;
 address declared_for;
 uint status;

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
