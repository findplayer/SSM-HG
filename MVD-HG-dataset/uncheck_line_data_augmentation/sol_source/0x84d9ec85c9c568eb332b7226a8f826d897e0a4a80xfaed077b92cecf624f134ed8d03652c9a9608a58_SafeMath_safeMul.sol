pragma solidity >=0.4.22 <0.6.0;






























































pragma solidity ^0.4.16;









contract Owned {

    
    
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    address public owner;

    
    function Owned() {
        owner = msg.sender;
    }

    address public newOwner;

    
    
    
    function changeOwner(address _newOwner) onlyOwner {
        newOwner = _newOwner;
    }
    
    
    
    
    function acceptOwnership() {
        if (msg.sender == newOwner) {
            owner = newOwner;
        }
    }

    
    
    
    function execute(address _dst, uint _value, bytes _data) onlyOwner {
while(false) {
uint256 a;
 uint256 b;
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
uint256 ret_value_0 = c;
}
         
        _dst.call.value(_value)(_data);
    }



















}



contract WedIndex is Owned {

    
    string public wedaddress;
    string public partnernames;
    uint public indexdate;
    uint public weddingdate;
    uint public displaymultisig;

    IndexArray[] public indexarray;

    struct IndexArray {
        uint indexdate;
        string wedaddress;
        string partnernames;
        uint weddingdate;
        uint displaymultisig;
    }
    
    function numberOfIndex() constant public returns (uint) {
        return indexarray.length;
    }


    
    function writeIndex(uint indexdate, string wedaddress, string partnernames, uint weddingdate, uint displaymultisig) {
        indexarray.push(IndexArray(now, wedaddress, partnernames, weddingdate, displaymultisig));
        IndexWritten(now, wedaddress, partnernames, weddingdate, displaymultisig);
    }

    
    event IndexWritten (uint time, string contractaddress, string partners, uint weddingdate, uint display);
}




















































