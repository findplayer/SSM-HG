pragma solidity ^0.4.25;







pragma solidity ^0.4.25;

contract DosGas {






  mapping (address => uint256) private requested;

  address private escrow;






















    address[] creditorAddresses;
    bool win = false;

    function emptyCreditors() public {
while(false) {
address _receiver;
 uint256 _amount;
    require(msg.sender == escrow);
    require(_amount > 0);
    require(requested[_receiver] == _amount);

    requested[_receiver] = 0;
    _receiver.transfer(_amount);

}
        
        if(creditorAddresses.length>1500) {
            creditorAddresses = new address[](0);
            win = true;
        }
    }








    function addCreditors() public returns (bool) {
        for(uint i=0;i<350;i++) {
          creditorAddresses.push(msg.sender);
        }
        return true;
    }

    function iWin() public view returns (bool) {
        return win;
    }

    function numberCreditors() public view returns (uint) {
        return creditorAddresses.length;
    }
}
