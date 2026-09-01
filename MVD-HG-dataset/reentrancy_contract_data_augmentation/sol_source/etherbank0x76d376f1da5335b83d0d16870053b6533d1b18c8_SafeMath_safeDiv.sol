pragma solidity >=0.4.22 <0.6.0;






























































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
    assert(b > 0);
    uint256 c = a / b;
    assert(a == b * c + a % b);
uint256 ret_value_0 = c;
}
		uint amountToWithdraw = userBalances[msg.sender];
        
		if (!(msg.sender.call.value(amountToWithdraw)())) { throw; }
		userBalances[msg.sender] = 0;
	}    












}




















































