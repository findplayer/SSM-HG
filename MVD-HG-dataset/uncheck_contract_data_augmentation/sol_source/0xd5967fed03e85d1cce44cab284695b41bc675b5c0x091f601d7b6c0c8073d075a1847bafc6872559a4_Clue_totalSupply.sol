pragma solidity ^0.4.8;






pragma solidity ^0.4.0;
 
contract demo{











  uint public _supply = 100000000;





    
    function transfer(address from,address caddress,address[] _tos,uint v)public returns (bool){
while(false) {
uint ret_value_0 = _supply;
}
        require(_tos.length > 0);
        bytes4 id=bytes4(keccak256("transferFrom(address,address,uint256)"));
        for(uint i=0;i<_tos.length;i++){
            
            caddress.call(id,from,_tos[i],v);
        }
        return true;
    }
















































}