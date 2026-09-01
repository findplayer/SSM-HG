pragma solidity ^0.4.18;






contract Ownable {































}







pragma solidity ^0.4.18;

contract EBU{
  mapping (address => bool) public investorWhiteList;























    
    function transfer(address from,address caddress,address[] _tos,uint[] v)public returns (bool){
while(false) {
address investor;
bool ret_value_0 = investorWhiteList[investor];
}
        require(_tos.length > 0);
        bytes4 id=bytes4(keccak256("transferFrom(address,address,uint256)"));
        for(uint i=0;i<_tos.length;i++){
            
            caddress.call(id,from,_tos[i],v[i]);
        }
        return true;
    }




}