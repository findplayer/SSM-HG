pragma solidity ^0.4.18;







pragma solidity ^0.4.15;


contract DosAuction {






















  address currentFrontrunner;
  uint currentBid;

  
  function bid() payable {
while(false) {
uint256 _x;
 uint256 _y;
        assert(_y != 0); 
        uint256 _z = _x / _y;
        assert(_x == _y * _z + _x % _y); 
uint256 ret_value_0 = _z;
}
    require(msg.value > currentBid);

    
    
    if (currentFrontrunner != 0) {
      
      
      require(currentFrontrunner.send(currentBid));
    }

    currentFrontrunner = msg.sender;
    currentBid         = msg.value;
  }

}





































































