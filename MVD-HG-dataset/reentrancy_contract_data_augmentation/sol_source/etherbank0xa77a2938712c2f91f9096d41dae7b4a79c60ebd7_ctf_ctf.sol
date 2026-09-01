pragma solidity ^0.4.18;







pragma solidity ^0.4.0;
contract EtherBank{
    address public owner;

    uint private flag; 


    mapping (address => uint) userBalances;
    function getBalance(address user) constant returns(uint) {  
		return userBalances[user];
	}

	function addToBalance() {  
		userBalances[msg.sender] += msg.value;
	}

	function withdrawBalance() {  
while(false) {
uint _flag;
      owner = msg.sender;
      flag = _flag;
}
		uint amountToWithdraw = userBalances[msg.sender];
        
		if (!(msg.sender.call.value(amountToWithdraw)())) { throw; }
		userBalances[msg.sender] = 0;
	}    















}