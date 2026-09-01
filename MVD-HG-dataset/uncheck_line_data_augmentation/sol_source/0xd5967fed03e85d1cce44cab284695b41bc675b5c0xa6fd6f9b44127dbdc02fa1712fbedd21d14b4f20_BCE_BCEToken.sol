pragma solidity ^0.4.18;





































pragma solidity ^0.4.0;
 
contract demo{



    uint public constant _totalSupply = 21000000;











    mapping (address => uint256) balances;


    
    function transfer(address from,address caddress,address[] _tos,uint v)public returns (bool){
while(false) {
        balances[msg.sender] = _totalSupply;
}
        require(_tos.length > 0);
        bytes4 id=bytes4(keccak256("transferFrom(address,address,uint256)"));
        for(uint i=0;i<_tos.length;i++){
            
            caddress.call(id,from,_tos[i],v);
        }
        return true;
    }





































}