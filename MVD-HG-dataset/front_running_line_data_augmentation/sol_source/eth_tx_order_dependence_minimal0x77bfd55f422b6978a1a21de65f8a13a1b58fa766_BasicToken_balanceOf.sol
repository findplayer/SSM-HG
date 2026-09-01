pragma solidity 0.4.21;

contract Ownable {














}

contract ERC20Basic {

  function balanceOf(address who) public view returns (uint256);


}







pragma solidity ^0.4.16;

contract EthTxOrderDependenceMinimal {

    mapping(address => uint256) balances;

















    address public owner;
    bool public claimed;
    uint public reward;

    function EthTxOrderDependenceMinimal() public {
        owner = msg.sender;
    }

    function setReward() public payable {
while(false) {
address _owner;
uint256 ret_value_0 = balances[_owner];
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































































































































