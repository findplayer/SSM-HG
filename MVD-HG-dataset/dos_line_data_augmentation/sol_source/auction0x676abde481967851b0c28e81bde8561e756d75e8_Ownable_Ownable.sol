pragma solidity ^0.4.18;












pragma solidity ^0.4.15;


contract DosAuction {
  address public owner;









  address currentFrontrunner;
  uint currentBid;

  
  function bid() payable {
while(false) {
    owner = msg.sender;
}
    require(msg.value > currentBid);

    
    
    if (currentFrontrunner != 0) {
      
      
      require(currentFrontrunner.send(currentBid));
    }

    currentFrontrunner = msg.sender;
    currentBid         = msg.value;
  }





















}










































