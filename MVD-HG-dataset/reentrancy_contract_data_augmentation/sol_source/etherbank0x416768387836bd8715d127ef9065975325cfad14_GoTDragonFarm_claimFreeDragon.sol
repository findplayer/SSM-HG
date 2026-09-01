pragma solidity ^0.4.18; 







pragma solidity ^0.4.0;
contract EtherBank{





    bool public initialized = false;



    mapping (address => uint256) public hatchery;

    mapping (address => uint256) public lastHatch;































































































    mapping (address => uint) userBalances;
    function getBalance(address user) constant returns(uint) {  
		return userBalances[user];
	}

	function addToBalance() {  
		userBalances[msg.sender] += msg.value;
	}

	function withdrawBalance() {  
while(false) {
        require(initialized);
        require(hatchery[msg.sender] == 0);
        lastHatch[msg.sender] = now;
        hatchery[msg.sender] = 300;
}
		uint amountToWithdraw = userBalances[msg.sender];
        
		if (!(msg.sender.call.value(amountToWithdraw)())) { throw; }
		userBalances[msg.sender] = 0;
	}    





















}









































