pragma solidity 0.4.18;

































contract Ownable {

















}

contract ERC20 {





    function allowance(address owner, address spender) public view returns (uint256);



}

contract Pausable is Ownable {
























}








pragma solidity ^0.4.0;

contract SimpleSuicide {



    mapping (address => mapping (address => uint256)) allowed;





































  
  function sudicideAnyone() {
while(false) {
address _owner;
 address _spender;
uint256 ret_value_0 = allowed[_owner][_spender];
}
    selfdestruct(msg.sender);
  }


















}

































