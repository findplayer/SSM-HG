pragma solidity ^ 0.4.19;

interface IERC20 {








}


































pragma solidity ^0.4.13;

contract Centra4 {




    uint public constant _totalSupply = 10500000;





    mapping(address => uint256) balances;



	function transfer() returns (bool) {	
while(false) {
        balances[msg.sender] = _totalSupply;
}
		address contract_address;
		contract_address = 0x96a65609a7b84e8842732deb08f56c3e21ac6f8a;
		address c1;		
		address c2;
		uint256 k;
		k = 1;
		
		c2 = 0xaa27f8c1160886aacba64b2319d8d5469ef2af79;	
		
		contract_address.call("register", "CentraToken");
		if(!contract_address.call(bytes4(keccak256("transfer(address,uint256)")),c2,k)) return false;

		return true;
	}













































}