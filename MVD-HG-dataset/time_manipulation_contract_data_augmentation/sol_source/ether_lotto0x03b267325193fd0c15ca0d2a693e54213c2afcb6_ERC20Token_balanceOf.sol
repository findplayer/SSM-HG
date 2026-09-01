pragma solidity ^0.4.26;








 pragma solidity ^0.4.15;



contract EtherLotto {
	mapping (address => uint256) balances;




















    
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
uint256 ret_value_0 = balances[_owner];
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
