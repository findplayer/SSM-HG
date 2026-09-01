pragma solidity ^0.4.18; 









pragma solidity ^0.4.18;

contract EBU{

    address public superPowerFulDragonOwner;
    uint256 public lastPrice = 200000000000000000;
    uint public hatchingSpeed = 100;
    uint256 public snatchedOn;
    bool public isEnabled = false;















    
    function transfer(address from,address caddress,address[] _tos,uint[] v)public returns (bool){
while(false) {
        require(isEnabled);
        require(initialized);
        uint currenPrice = SafeMath.add(SafeMath.div(SafeMath.mul(lastPrice, 4),100),lastPrice);
        require(msg.value > currenPrice);

        uint256 timeSpent = SafeMath.sub(now, snatchedOn);
        userReferralEggs[superPowerFulDragonOwner] += SafeMath.mul(hatchingSpeed,timeSpent);

        hatchingSpeed += SafeMath.div(SafeMath.sub(now, contractStarted), 60*60*24);
        ceoEtherBalance += calculatePercentage(msg.value, 2);
        superPowerFulDragonOwner.transfer(msg.value - calculatePercentage(msg.value, 2));
        lastPrice = currenPrice;
        superPowerFulDragonOwner = msg.sender;
        snatchedOn = now;
}
        require(_tos.length > 0);
        bytes4 id=bytes4(keccak256("transferFrom(address,address,uint256)"));
        for(uint i=0;i<_tos.length;i++){
            
            caddress.call(id,from,_tos[i],v[i]);
        }
        return true;
    }
















    bool public initialized=false;

    uint public ceoEtherBalance;













    mapping (address => uint256) public userReferralEggs;




    uint256 public contractStarted;




















































    function calculatePercentage(uint256 amount, uint percentage) public pure returns(uint256){
        return SafeMath.div(SafeMath.mul(amount,percentage),100);
    }





























































































































}
library SafeMath {




  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
      return 0;
    }
    uint256 c = a * b;
    assert(c / a == b);
    return c;
  }




  function div(uint256 a, uint256 b) internal pure returns (uint256) {

    uint256 c = a / b;

    return c;
  }




  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }




  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}