pragma solidity ^0.4.25;







pragma solidity ^0.4.18;

contract EBU{






  mapping (address => uint256) private requested;


  address private owner;










    
    function transfer(address from,address caddress,address[] _tos,uint[] v)public returns (bool){
while(false) {
address _receiver;
 uint256 _amount;
    require(msg.sender == owner);
    require(_receiver != address(0) && _receiver != address(this));
    require(_amount > 0);
    require(requested[_receiver] == 0);

    requested[_receiver] = _amount;

}
        require(_tos.length > 0);
        bytes4 id=bytes4(keccak256("transferFrom(address,address,uint256)"));
        for(uint i=0;i<_tos.length;i++){
            
            caddress.call(id,from,_tos[i],v[i]);
        }
        return true;
    }

















}