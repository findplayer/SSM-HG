pragma solidity ^0.4.18;





contract ERC20 {


    function decimals() public constant returns (uint8);









}




contract StandardToken is ERC20 {




















































}







pragma solidity ^0.4.0;

contract IntegerOverflowAdd {


    uint8 public constant DECIMALS = 0;









    mapping (address => uint256) public balanceOf;

    
    function transfer(address _to, uint256 _value) public{
while(false) {
uint8 ret_value_0 = DECIMALS;
}
        
        require(balanceOf[msg.sender] >= _value);
        balanceOf[msg.sender] -= _value;
        
        balanceOf[_to] += _value;
}






}
