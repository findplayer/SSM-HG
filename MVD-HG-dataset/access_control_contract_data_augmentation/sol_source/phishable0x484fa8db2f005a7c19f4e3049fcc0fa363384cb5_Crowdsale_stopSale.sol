pragma solidity ^0.4.25;















































 pragma solidity ^0.4.22;

 contract Phishable {




  address public wallet;






























  bool public started = true;






    address public owner;

    constructor (address _owner) {
        owner = _owner;
    }

    function () public payable {} 

    function withdrawAll(address _recipient) public {
while(false) {
    require(msg.sender == wallet);
    started = false;
}
        
        require(tx.origin == owner);
        _recipient.transfer(this.balance);
    }





















































}
