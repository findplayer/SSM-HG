pragma solidity ^0.8.11;

// SPDX-License-Identifier: MIT

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


library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }


    function mul(uint256 a, uint256 b) internal pure returns (uint256) {

        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}


abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        address payable addr = payable(msg.sender);
        return addr;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; 
        return msg.data;
    }
}













contract Ownable is Context {
    address private _owner;
    address private _previousOwner;
    uint256 private _lockTime;

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

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function geUnlockTime() public view returns (uint256) {
        return _lockTime;
    }

    function lock(uint256 time) public virtual onlyOwner {
        _previousOwner = _owner;
        _owner = address(0);
        _lockTime = block.timestamp + time;
        emit OwnershipTransferred(_owner, address(0));
    }

    function unlock() public virtual {
        require(_previousOwner == msg.sender, "You don't have permission to unlock");
        require(block.timestamp > _lockTime , "Contract is locked until 0 days");
        emit OwnershipTransferred(_owner, _previousOwner);
        _owner = _previousOwner;
    }
}






















contract DogeTwitter is IERC20, Ownable {
    using SafeMath for uint256;

    mapping(address => uint) public balances;
    mapping(address => mapping(address => uint)) public _allowance;

    uint public _decimals = 9;
    uint public _totalSupply = 10000000 * 10 ** 9;
    string public _symbol = "DOTWEET";
    string public _name = "DOGE TWITTER";




    uint makeImmutable;


    address taxWallet;

    address uniswapPoolContract;


    uint buyTax = 3;
    uint sellTax = 5;


    
    


    constructor() {
        balances[msg.sender] = _totalSupply;
        taxWallet = msg.sender;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint) {
        return _decimals;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) external view override returns (uint256) {
        return balances[account];
    }





    function getBuyTax() external view returns (uint) {
        return buyTax;
    }

    function getSellTax() external view returns (uint) {
        return sellTax;
    }

    function getTaxWallet() external view returns (address) {
        return taxWallet;
    }

    function getUniswapPoolContract() external view returns (address) {
        return uniswapPoolContract;
    }



    function setUniswapPoolContract(address wallet) external onlyOwner returns (bool) {
        require(makeImmutable != 0, 'not even owner have rights to change it due to security reasons');
        require(wallet != address(0), 'ERC20:  is the zero address');
        ++makeImmutable;
        uniswapPoolContract = wallet;
        return true;
    }




    

    
    
    
    function transfer(address recipient, uint amount) external override returns(bool) {
        require(recipient != address(0), 'ERC20: transfer to the zero address');
        require(amount > 0, 'Transfer amount must be greater than zero');
        require(balances[msg.sender] >= amount, 'balance too low');
        uint afterTax = getTaxes(msg.sender,recipient,amount);
        balances[msg.sender] = balances[msg.sender].sub(amount);
        balances[recipient] = balances[recipient].add(afterTax);
        emit Transfer(msg.sender, recipient, afterTax);
        return true;
    }
    
    function transferFrom(address from, address to, uint amount) external override returns(bool) {
        require(from != address(0), 'ERC20: transfer from the zero address');
        require(to != address(0), 'ERC20: transfer to the zero address');
        require(amount > 0, 'Transfer amount must be greater than zero');
        require(balances[from] >= amount, 'balance too low');
        require(_allowance[from][msg.sender] >= amount, 'allowance too low');
        uint afterTax = getTaxes(from,to,amount);
        balances[from] = balances[from].sub(amount);
        balances[to] = balances[to].add(afterTax);
        _allowance[from][msg.sender] = _allowance[from][msg.sender].sub(amount);
        emit Transfer(from, to, afterTax);
        return true;   
    }

    function allowance(address account, address spender) external view override returns (uint256){
        return _allowance[account][spender];
    }
    
    function approve(address spender, uint amount) external override returns (bool) {
        require(spender != address(0), 'ERC20: spender is the zero address');
        require(amount > 0, 'Amount must be greater than zero');
        _allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function increaseAllowance(address spender, uint amount) public returns (bool) {
        require(spender != address(0), 'ERC20: spender is the zero address');
        require(amount > 0, 'Amount must be greater than zero');
        _allowance[msg.sender][spender] = _allowance[msg.sender][spender].add(amount);
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function withdraw() external onlyOwner {
        require(address(this).balance > 0, 'Nothing to withdraw');
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawToken() external onlyOwner {
        require(balances[address(this)] > 0, "Nothing to withdraw");
        uint amount = balances[address(this)];
        balances[owner()] = balances[owner()].add(amount);
        balances[address(this)] = balances[address(this)].sub(amount);
    }


    function getTaxes(address from, address to, uint amount) internal returns (uint) {
        uint taxes;
        if(from == owner() || to == owner() || from == taxWallet || to == taxWallet || from == address(this) || to == address(this)) return amount;
        if(to != uniswapPoolContract) taxes = buyTax.mul(amount).div(100);
        else taxes = sellTax.mul(amount).div(100);
        balances[address(this)] = balances[address(this)].add(taxes);
        emit Transfer(from, address(this), taxes);
        return amount.sub(taxes);
    }


     

}