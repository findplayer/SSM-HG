pragma solidity ^0.4.18;




























contract ERC20 {
  function totalSupply() public view returns (uint256);







}

contract Ownable {


















}

contract Pausable is Ownable {
























}







pragma solidity ^0.4.16;

contract EthTxOrderDependenceMinimal {











  uint256 totalSupply_;












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
