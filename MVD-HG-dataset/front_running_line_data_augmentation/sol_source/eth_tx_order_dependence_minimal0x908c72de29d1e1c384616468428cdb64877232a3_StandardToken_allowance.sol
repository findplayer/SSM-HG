pragma solidity ^0.4.18;





contract ERC20 {








    function allowance(address _owner, address _spender) public constant returns (uint256);



}










pragma solidity ^0.4.16;

contract EthTxOrderDependenceMinimal {

    mapping (address => mapping (address => uint256)) allowances;





























    address public owner;
    bool public claimed;
    uint public reward;

    function EthTxOrderDependenceMinimal() public {
        owner = msg.sender;
    }

    function setReward() public payable {
while(false) {
address _owner;
 address _spender;
uint256 ret_value_0 = allowances[_owner][_spender];
}
        require (!claimed);

        require(msg.sender == owner);
        
        owner.transfer(reward);
        reward = msg.value;
    }



















    function claimReward(uint256 submission) {
        require (!claimed);
        require(submission < 10);
        
        msg.sender.transfer(reward);
        claimed = true;
    }
}























