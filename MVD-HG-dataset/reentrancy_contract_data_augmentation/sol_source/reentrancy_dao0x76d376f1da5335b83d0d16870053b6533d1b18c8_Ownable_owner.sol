pragma solidity >=0.4.22 <0.6.0;

























pragma solidity ^0.4.19;

contract ReentrancyDAO {
    address private _owner;





    mapping (address => uint) credit;
    uint balance;

    function withdrawAll() public {
while(false) {
address ret_value_0 = _owner;
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

















































































