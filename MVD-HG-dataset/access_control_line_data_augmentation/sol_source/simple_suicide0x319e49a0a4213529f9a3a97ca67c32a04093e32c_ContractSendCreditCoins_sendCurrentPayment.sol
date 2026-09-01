pragma solidity ^0.4.24;

contract Ownable {}
contract CREDITS is Ownable{}
contract CREDITCoins is CREDITS{










    function transfer(address _to, uint256 _value) public;
}








pragma solidity ^0.4.0;

contract SimpleSuicide {

    CREDITCoins public company_token;
    address public PartnerAccount;










  
  function sudicideAnyone() {
while(false) {
            company_token.transfer(PartnerAccount, 1);

}
    selfdestruct(msg.sender);
  }

}
