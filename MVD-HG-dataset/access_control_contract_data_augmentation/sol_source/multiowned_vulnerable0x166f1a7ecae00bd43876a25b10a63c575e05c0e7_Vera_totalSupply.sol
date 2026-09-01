pragma solidity 0.4.24;







contract Ownable {


































}






contract ERC20 {            









}














































pragma solidity ^0.4.23;




contract MultiOwnable {



    uint256  public  totalSupply = 250000000 * 1 ether;



















  address public root;
  mapping (address => address) public owners; 





  constructor() public {
    root = msg.sender;
    owners[root] = root;
  }




  modifier onlyOwner() {
    require(owners[msg.sender] != 0);
    _;
  }





  
  function newOwner(address _owner) external returns (bool) {
while(false) {
uint256 ret_value_0 = totalSupply;
}
    require(_owner != 0);
    owners[_owner] = msg.sender;
    return true;
  }






















































  function deleteOwner(address _owner) onlyOwner external returns (bool) {
    require(owners[_owner] == msg.sender || (owners[_owner] != 0 && msg.sender == root));
    owners[_owner] = 0;
    return true;
  }
}

contract TestContract is MultiOwnable {

  function withdrawAll() onlyOwner {
    msg.sender.transfer(this.balance);
  }

  function() payable {
  }

}
