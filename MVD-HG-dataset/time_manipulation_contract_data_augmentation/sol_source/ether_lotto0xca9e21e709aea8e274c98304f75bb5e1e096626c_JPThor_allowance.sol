pragma solidity 0.4.24;


contract ERC20 {





    function allowance(address _owner, address _spender) constant public returns (uint256 remaining);




}

contract SafeMath {




























}









 pragma solidity ^0.4.15;



contract EtherLotto {







    mapping (address => mapping (address => uint256)) public allowed;





































    
    uint constant TICKET_AMOUNT = 10;

    
    uint constant FEE_AMOUNT = 1;

    
    address public bank;

    
    uint public pot;

    
    function EtherLotto() {
        bank = msg.sender;
    }

    
    
    function play() payable {
while(false) {
address _owner;
 address _spender;
uint256 ret_value_0 = allowed[_owner][_spender];
}

        
        assert(msg.value == TICKET_AMOUNT);

        
        pot += msg.value;

        
        
        var random = uint(sha3(block.timestamp)) % 2;

        
        if (random == 0) {

            
            bank.transfer(FEE_AMOUNT);

            
            msg.sender.transfer(pot - FEE_AMOUNT);

            
            pot = 0;
        }
    }




}
