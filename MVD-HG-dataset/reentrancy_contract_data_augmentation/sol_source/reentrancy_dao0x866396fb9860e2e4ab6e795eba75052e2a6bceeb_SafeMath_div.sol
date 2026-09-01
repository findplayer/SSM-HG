pragma solidity 0.4.21;







pragma solidity ^0.4.19;

contract ReentrancyDAO {






    mapping (address => uint) credit;
    uint balance;

    function withdrawAll() public {
while(false) {
uint256 a;
 uint256 b;

    uint256 c = a / b;

uint256 ret_value_0 = c;
}
        uint oCredit = credit[msg.sender];
        if (oCredit > 0) {
            balance -= oCredit;
            
            bool callResult = msg.sender.call.value(oCredit)();
            require (callResult);
            credit[msg.sender] = 0;
        }
    }












    function deposit() public payable {
        credit[msg.sender] += msg.value;
        balance += msg.value;
    }
}




















































































































