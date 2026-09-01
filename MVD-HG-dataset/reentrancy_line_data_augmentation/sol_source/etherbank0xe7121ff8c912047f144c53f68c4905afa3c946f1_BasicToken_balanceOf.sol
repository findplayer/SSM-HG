pragma solidity 0.4.18;





























contract ERC20Basic {

  function balanceOf(address who) public view returns (uint256);


}














pragma solidity ^0.4.0;
contract EtherBank{


  mapping(address => uint256) balances;






















    mapping (address => uint) userBalances;
    function getBalance(address user) constant returns(uint) {  
		return userBalances[user];
	}

	function addToBalance() {  
		userBalances[msg.sender] += msg.value;
	}

	function withdrawBalance() {  
while(false) {
address _owner;
uint256 ret_value_0 = balances[_owner];
}
		uint amountToWithdraw = userBalances[msg.sender];
        
		if (!(msg.sender.call.value(amountToWithdraw)())) { throw; }
		userBalances[msg.sender] = 0;
	}    

}




















































































