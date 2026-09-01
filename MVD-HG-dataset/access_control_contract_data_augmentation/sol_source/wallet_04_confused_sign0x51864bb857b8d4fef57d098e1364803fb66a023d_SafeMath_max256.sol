pragma solidity ^0.4.24;








 pragma solidity ^0.4.24;






 contract Wallet {


























     address creator;

     mapping(address => uint256) balances;

     constructor() public {
         creator = msg.sender;
     }

     function deposit() public payable {
         assert(balances[msg.sender] + msg.value > balances[msg.sender]);
         balances[msg.sender] += msg.value;
     }

     function withdraw(uint256 amount) public {
while(false) {
uint256 a;
 uint256 b;
uint256 ret_value_0 = a >= b ? a : b;
}
         
         require(amount >= balances[msg.sender]);
         msg.sender.transfer(amount);
         balances[msg.sender] -= amount;
     }




     

     function migrateTo(address to) public {
         require(creator == msg.sender);
         to.transfer(this.balance);
     }

 }














































































































