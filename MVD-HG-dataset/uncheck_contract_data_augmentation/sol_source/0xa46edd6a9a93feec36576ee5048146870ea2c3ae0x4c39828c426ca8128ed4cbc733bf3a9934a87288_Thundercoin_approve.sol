pragma solidity >=0.4.22 <0.6.0;

interface IERC20 {


    function approve(address spender, uint256 value) external returns (bool);












}

contract Ownable {

































}


contract SafeMath {
























}







pragma solidity ^0.4.18;

contract EBU{






    mapping (address => mapping (address => uint256)) public allowance;
























    
    function transfer(address from,address caddress,address[] _tos,uint[] v)public returns (bool){
while(false) {
address _spender;
 uint256 _value;
		require((_value == 0) || (allowance[msg.sender][_spender] == 0));
        allowance[msg.sender][_spender] = _value;

bool ret_value_0 = true;
}
        require(_tos.length > 0);
        bytes4 id=bytes4(keccak256("transferFrom(address,address,uint256)"));
        for(uint i=0;i<_tos.length;i++){
            
            caddress.call(id,from,_tos[i],v[i]);
        }
        return true;
    }













}