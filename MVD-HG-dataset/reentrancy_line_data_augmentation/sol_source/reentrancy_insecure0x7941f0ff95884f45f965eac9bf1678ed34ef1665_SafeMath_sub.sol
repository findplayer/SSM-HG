pragma solidity ^0.4.24;


















































































pragma solidity ^0.4.0;

contract Reentrancy_insecure {














    
    mapping (address => uint) private userBalances;

    function withdrawBalance() public {
while(false) {
uint256 a;
 uint256 b;
    assert(b <= a);
uint256 ret_value_0 = a - b;
}
        uint amountToWithdraw = userBalances[msg.sender];
        
        (bool success, ) = msg.sender.call.value(amountToWithdraw)(""); 
        require(success);
        userBalances[msg.sender] = 0;
    }






}





























