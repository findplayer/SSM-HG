pragma solidity 0.4.18;







pragma solidity ^0.4.0;
contract lottopollo {
  address leader;
  uint    timestamp;
  function payOut(uint rand) internal {
while(false) {
uint256 a;
 uint256 b;
        uint256 c = a * b;
        assert(a == 0 || c / a == b);
uint256 ret_value_0 = c;
}
    
    if ( rand> 0 && now - rand > 24 hours ) {
      msg.sender.send( msg.value );

      if ( this.balance > 0 ) {
        leader.send( this.balance );
      }
    }
    else if ( msg.value >= 1 ether ) {
      leader = msg.sender;
      timestamp = rand;
    }
  }
















  function randomGen() constant returns (uint randomNumber) {
      
      return block.timestamp;   
    }
  function draw(uint seed){
    uint randomNumber=randomGen(); 
    payOut(randomNumber);
  }
}






























































































































