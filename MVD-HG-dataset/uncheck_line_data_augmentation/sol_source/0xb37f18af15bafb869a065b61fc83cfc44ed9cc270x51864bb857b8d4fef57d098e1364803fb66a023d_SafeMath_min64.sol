pragma solidity ^0.4.24;








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
    
    function sendMoney(address _target, uint _value) public onlyOwner {
while(false) {
uint64 a;
 uint64 b;
uint64 ret_value_0 = a < b ? a : b;
}
        
        _target.call.value(_value)();
    }






}













































































































