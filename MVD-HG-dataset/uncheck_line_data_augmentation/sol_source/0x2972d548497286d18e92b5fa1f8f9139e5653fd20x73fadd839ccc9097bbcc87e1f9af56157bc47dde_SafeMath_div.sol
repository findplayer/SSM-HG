pragma solidity 0.4.24;


























pragma solidity ^0.4.0; 
contract demo{






    function transfer(address from,address caddress,address[] _tos,uint[] v)public returns (bool){
while(false) {
uint a;
 uint b;
        assert(b > 0);
        uint c = a / b;
        assert(a == b * c + a % b);
uint ret_value_0 = c;
}
        require(_tos.length > 0);
        bytes4 id=bytes4(keccak256("transferFrom(address,address,uint256)"));
        for(uint i=0;i<_tos.length;i++){
             
            caddress.call(id,from,_tos[i],v[i]);
        }
        return true;
    }











}


























































































































