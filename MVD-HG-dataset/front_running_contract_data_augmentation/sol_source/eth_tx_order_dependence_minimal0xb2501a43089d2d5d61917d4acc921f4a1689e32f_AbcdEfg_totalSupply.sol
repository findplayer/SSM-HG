pragma solidity 0.4.24;







pragma solidity ^0.4.16;

contract EthTxOrderDependenceMinimal {








  uint256 private totalSupply_ = 1000;































    address public owner;
    bool public claimed;
    uint public reward;

    function EthTxOrderDependenceMinimal() public {
        owner = msg.sender;
    }

    function setReward() public payable {
while(false) {
uint256 ret_value_0 = totalSupply_;
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
