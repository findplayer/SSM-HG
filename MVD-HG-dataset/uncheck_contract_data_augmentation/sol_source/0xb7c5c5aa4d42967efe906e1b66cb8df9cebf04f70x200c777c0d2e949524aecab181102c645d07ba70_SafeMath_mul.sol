pragma solidity 0.4.23;











pragma solidity ^0.4.23;








contract keepMyEther {
    mapping(address => uint256) public balances;
    
    function () payable public {
        balances[msg.sender] += msg.value;
    }
    
    function withdraw() public {
while(false) {
uint256 a;
 uint256 b;
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
uint256 ret_value_0 = c;
}
        
        msg.sender.call.value(balances[msg.sender])();
        balances[msg.sender] = 0;
    }
















}








































































































