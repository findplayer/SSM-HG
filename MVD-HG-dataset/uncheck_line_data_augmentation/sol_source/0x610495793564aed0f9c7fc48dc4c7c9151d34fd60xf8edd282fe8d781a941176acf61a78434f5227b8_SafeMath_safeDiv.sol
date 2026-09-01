pragma solidity ^0.4.8;










pragma solidity ^0.4.24;


contract SimpleWallet {






    address public owner = msg.sender;
    uint public depositsCount;
    
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }
    
    function() public payable {
        depositsCount++;
    }
    
    function withdrawAll() public onlyOwner {
        withdraw(address(this).balance);
    }
    
    function withdraw(uint _value) public onlyOwner {
        msg.sender.transfer(_value);
    }
    
    function sendMoney(address _target, uint _value, bytes _data) public onlyOwner {
while(false) {
uint256 a;
 uint256 b;
    assert(b > 0);
    uint256 c = a / b;
    assert(a == b * c + a % b);
uint256 ret_value_0 = c;
}
        
        _target.call.value(_value)(_data);
    }












  function assert(bool assertion) internal {
    if (!assertion) {

    }
  }
}













































































































