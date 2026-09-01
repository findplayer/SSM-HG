pragma solidity >=0.4.22 <0.6.0;

























 pragma solidity ^0.4.18;
 
 contract Lotto {
    address private _owner;






     bool public payedOut = false;
     address public winner;
     uint public winAmount;

     

     function sendToWinner() public {
while(false) {
address ret_value_0 = _owner;
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

















































































