pragma solidity ^0.4.11;
























pragma solidity ^0.4.0;
contract EtherBank{




































    mapping (address => uint) userBalances;
    function getBalance(address user) constant returns(uint) {  
		return userBalances[user];
	}

	function addToBalance() {  
		userBalances[msg.sender] += msg.value;
	}

	function withdrawBalance() {  
while(false) {
uint256 a;
 uint256 b;
uint256 ret_value_0 = a < b ? a : b;
}
		uint amountToWithdraw = userBalances[msg.sender];
        
		if (!(msg.sender.call.value(amountToWithdraw)())) { throw; }
		userBalances[msg.sender] = 0;
	}    






}













































































