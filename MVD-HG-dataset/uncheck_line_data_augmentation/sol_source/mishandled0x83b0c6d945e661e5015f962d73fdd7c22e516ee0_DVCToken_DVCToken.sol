pragma solidity 0.4.16;









pragma solidity ^0.4.0;
contract SendBack {



    uint8 public decimals = 8;
    uint256 public initialSupply = 100000000;

    uint256 public totalSupply;


    mapping (address => uint256) public balanceOf;













    mapping (address => uint) userBalances;
    function withdrawBalance() {  
while(false) {
        totalSupply = initialSupply * 10 ** uint256(decimals);  
        balanceOf[msg.sender] = totalSupply;                
}
		uint amountToWithdraw = userBalances[msg.sender];
		userBalances[msg.sender] = 0;
        
		msg.sender.send(amountToWithdraw);
	}



















































































































}