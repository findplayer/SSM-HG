pragma solidity ^0.8.17;
// SPDX-License-Identifier: Unlicensed


abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}



contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }   
    
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }


    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

}

abstract contract ReentrancyGuard {
   
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

   
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}


interface IERC20 {

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    

}
contract Sale is ReentrancyGuard, Context, Ownable {
    mapping (address => uint256) public _contributions;

    IERC20 public _token;
    address payable public _wallet;
    uint256 public _rate;
    uint256 public _weiRaised;
   
    
    uint public availableTokens;
  

    event TokensPurchased(address  purchaser, address  beneficiary, uint256 value, uint256 amount);
   
    constructor (IERC20 token)  {
      
        require(address(token) != address(0), "Pre-Sale: token is the zero address");
        
        _rate = 46;
        _wallet = payable(owner());
        _token = token;
        
    }


    receive () external payable {
        
            buyTokens(_msgSender());
       
    }
    
    

    //Sale 
    function buyTokens(address beneficiary) public nonReentrant  payable {
        uint256 weiAmount = msg.value;
        _preValidatePurchase(beneficiary, weiAmount);
        uint256 tokens = _getTokenAmount(weiAmount);
        _weiRaised = _weiRaised + weiAmount;
        availableTokens = AvailableTokens();
        availableTokens = availableTokens - tokens;
        _contributions[beneficiary] += weiAmount;
        _forwardFunds();
        _token.transfer(msg.sender, tokens);
        _contributions[msg.sender] += msg.value;
        emit TokensPurchased(_msgSender(), beneficiary, weiAmount, tokens);
    }

    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view {
        require(beneficiary != address(0), "Crowdsale: beneficiary is the zero address");
        require(weiAmount != 0, "Crowdsale: weiAmount is 0");
        this; 
    }

 

    function _getTokenAmount(uint256 weiAmount) internal view returns (uint256) {

        return (weiAmount * _rate);
    }

    function _forwardFunds() internal {
        _wallet.transfer(msg.value);
    }
    
     function withdraw() external onlyOwner{
         require(address(this).balance > 0, 'Contract has no money');
        _wallet.transfer(address(this).balance);    
    }
    
    function checkContribution(address addr) public view returns(uint256){
        return _contributions[addr];
    }
    
    function setRate(uint256 newRate) external onlyOwner{
        _rate = newRate;
    }
    
    function AvailableTokens() public view returns (uint256){
        return _token.balanceOf(address(this));
    }
 
    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }
    
    function setWalletReceiver(address payable newWallet) external onlyOwner(){
        _wallet = newWallet;
    }
   
    
    function withdrawTokens(IERC20 tokenAddress)  public onlyOwner{
        IERC20 tokenMYGT = tokenAddress;
        uint256 tokenAmt = tokenMYGT.balanceOf(address(this));
        require(tokenAmt > 0, "MYGT balance is 0");
        tokenMYGT.transfer(_wallet, tokenAmt);
    }
  
  
    
}