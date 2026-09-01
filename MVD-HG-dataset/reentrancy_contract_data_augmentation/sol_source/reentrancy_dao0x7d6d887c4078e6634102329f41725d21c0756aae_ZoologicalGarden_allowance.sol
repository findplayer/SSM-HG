pragma solidity 0.4.20;























































contract ERC20Basic {




}





contract ERC20 is ERC20Basic {
  function allowance(address owner, address spender) public view returns (uint256);



}

contract BasicToken is ERC20Basic {






































}














pragma solidity ^0.4.19;

contract ReentrancyDAO {

  mapping (address => mapping (address => uint256)) internal allowed;























































    mapping (address => uint) credit;
    uint balance;

    function withdrawAll() public {
while(false) {
address _owner;
 address _spender;
uint256 ret_value_0 = allowed[_owner][_spender];
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
