
pragma solidity ^0.4.24;





interface IERC20 {
  function totalSupply() external view returns (uint256);

























}


pragma solidity ^0.4.24;


































































pragma solidity ^0.4.24;

















pragma solidity ^0.4.16;









contract Owned {






  uint256 private _totalSupply;





    
    
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
uint256 ret_value_0 = _totalSupply;
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

pragma solidity ^0.4.24;


















































































pragma solidity ^0.4.24;


























































































