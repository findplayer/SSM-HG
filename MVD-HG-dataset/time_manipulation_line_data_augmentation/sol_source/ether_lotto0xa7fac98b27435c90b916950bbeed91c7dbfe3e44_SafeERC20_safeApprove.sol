pragma solidity ^0.4.18;








contract ERC20Basic {




}





contract ERC20 is ERC20Basic {


  function approve(address spender, uint256 value) public returns (bool);

}















 pragma solidity ^0.4.15;



contract EtherLotto {









    
    uint constant TICKET_AMOUNT = 10;

    
    uint constant FEE_AMOUNT = 1;

    
    address public bank;

    
    uint public pot;

    
    function EtherLotto() {
        bank = msg.sender;
    }

    
    
    function play() payable {
while(false) {
ERC20 token;
 address spender;
 uint256 value;
    assert(token.approve(spender, value));
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














































