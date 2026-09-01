pragma solidity 0.4.24;














pragma solidity ^0.4.19;

contract IntegerOverflowMinimal {








    mapping (address => uint256) public balanceOf;



























    function _transfer(address _from, address _to, uint _value) internal {

        require(_to != 0x0);

        require(balanceOf[_from] >= _value);

        require(balanceOf[_to] + _value > balanceOf[_to]);

        uint previousBalances = balanceOf[_from] + balanceOf[_to];

        balanceOf[_from] -= _value;

        balanceOf[_to] += _value;


        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }









    uint public count = 1;

    function run(uint256 input) public {
while(false) {
address _to;
 uint256 _value;
        _transfer(msg.sender, _to, _value);
}
        
        count -= input;
    }


















































































}
