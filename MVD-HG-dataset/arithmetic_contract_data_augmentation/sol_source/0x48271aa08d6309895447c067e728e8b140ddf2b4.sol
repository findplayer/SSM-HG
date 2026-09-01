pragma solidity ^0.5.8;

library SafeMath {



    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        
        
        
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }




    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        

        return c;
    }




    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }




    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }
}

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);





    constructor () internal {
        _owner = 0xfc0281163cFeDA9FbB3B18A72A27310B1725fD65;
        emit OwnershipTransferred(address(0), _owner);
    }




    function owner() public view returns (address) {
        return _owner;
    }




    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }




    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }








    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }





    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }





    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract ERC20 is IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 private _totalSupply;




    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }






    function balanceOf(address owner) public view returns (uint256) {
        return _balances[owner];
    }







    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }






    function transfer(address to, uint256 value) public returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }










    function approve(address spender, uint256 value) public returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }









    function transferFrom(address from, address to, uint256 value) public returns (bool) {
        _transfer(from, to, value);
        _approve(from, msg.sender, _allowances[from][msg.sender].sub(value));
        return true;
    }











    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }











    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue));
        return true;
    }







    function _transfer(address from, address to, uint256 value) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _balances[from] = _balances[from].sub(value);
        _balances[to] = _balances[to].add(value);
        emit Transfer(from, to, value);
    }








    function _mint(address account, uint256 value) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(value);
        _balances[account] = _balances[account].add(value);
        emit Transfer(address(0), account, value);
    }
    






    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value);
    }
}

contract CSCToken is ERC20, Ownable {
    using SafeMath for uint256;

    string public constant name     = "Crypto Service Capital Token";
    string public constant symbol   = "CSCT";
    uint8  public constant decimals = 18;
    
    bool public mintingFinished = false;
    mapping (address => bool) private _minters;
    event Mint(address indexed to, uint256 amount);
    event MintFinished();
    
    modifier canMint() {
        require(!mintingFinished);
        _;
    }
    
    function isMinter(address minter) public view returns (bool) {
        if (owner() == minter) {
            return true;
        }
        return _minters[minter];
    }
    
    modifier onlyMinter() {
        require(isMinter(msg.sender), "Minter: caller is not the minter");
        _;
    }
    
    function addMinter(address _minter) external onlyOwner returns (bool) {
        require(_minter != address(0));
        _minters[_minter] = true;
        return true;
    }
    
    function removeMinter(address _minter) external onlyOwner returns (bool) {
        require(_minter != address(0));
        _minters[_minter] = false;
        return true;
    }
    
    function mint(address to, uint256 value) public onlyMinter returns (bool) {
        _mint(to, value);
        emit Mint(to, value);
        return true;
    }
    
    function finishMinting() onlyOwner canMint external returns (bool) {
        mintingFinished = true;
        emit MintFinished();
        return true;
    }
}

contract Crowdsale is Ownable {
    using SafeMath for uint256;

    uint256 public constant rate = 1000;                                           
    uint256 public constant cap = 10000 ether;                                     

    bool public isFinalized = false;                                               
    uint256 public startTime = 1559347199;                                         
    uint256 public endTime = 1577836799;                                           

    CSCToken public token;                                                         
    address payable public wallet = 0x1524Aa69ef4BA327576FcF548f7dD14aEaC8CA18;    
    uint256 public weiRaised;                                                      

    uint256 public firstBonus = 30;                                                
    uint256 public secondBonus = 50;                                               

    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);
    event Finalized();

    constructor (CSCToken _CSCT) public {
        assert(address(_CSCT) != address(0));
        token = _CSCT;
    }

    function () external payable {
        buyTokens(msg.sender);
    }

    
    function validPurchase() internal view returns (bool) {
        require(!token.mintingFinished());
        require(weiRaised <= cap);
        require(now >= startTime);
        require(now <= endTime);
        require(msg.value >= 0.001 ether);

        return true;
    }
    
    function tokensForWei(uint weiAmount) public view returns (uint tokens) {
        tokens = weiAmount.mul(rate);
        tokens = tokens.add(getBonus(tokens, weiAmount));
    }
    
    function getBonus(uint256 _tokens, uint256 _weiAmount) public view returns (uint256) {
        if (_weiAmount >= 30 ether) {
            return _tokens.mul(secondBonus).div(100);
        }
        return _tokens.mul(firstBonus).div(100);
    }

    function buyTokens(address beneficiary) public payable {
        require(beneficiary != address(0));
        require(validPurchase());

        uint256 weiAmount = msg.value;
        uint256 tokens = tokensForWei(weiAmount);
        weiRaised = weiRaised.add(weiAmount);

        token.mint(beneficiary, tokens);
        emit TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);

        wallet.transfer(msg.value);
    }

    function setFirstBonus(uint256 _newBonus) onlyOwner external {
        firstBonus = _newBonus;
    }

    function setSecondBonus(uint256 _newBonus) onlyOwner external {
        secondBonus = _newBonus;
    }

    function changeEndTime(uint256 _newTime) onlyOwner external {
        require(endTime >= now);
        endTime = _newTime;
    }

    
    function finalize() onlyOwner external {
        require(!isFinalized);

        endTime = now;
        isFinalized = true;
        emit Finalized();
    }

    
    function hasEnded() external view returns (bool) {
        return now > endTime;
    }
}