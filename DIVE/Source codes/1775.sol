/**
Cloudinary
Anonymous, Private, and Secure Servers
For Your Decentralized Application and AI Machine Learning Application
Website  : https://cloudinary.io/
Docs     : https://docs.cloudinary.io/
Bot      : https://t.me/cloudinary_bot
Twitter  : https://twitter.com/cloudinaryio
Telegram : https://t.me/cloudinaryio
Medium   : https://cloudinaryio.medium.com/
YouTube  : https://www.youtube.com/@Cloudinaryio
 */

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
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

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract CloudinaryIo is Context, IERC20, Ownable {
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    address payable private _taxWallet;

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;

    string private constant _name = "Cloudinary";
    string private constant _symbol = "CDY";
    uint8 private constant _decimals = 9;
    uint256 private constant _totalSupply = 100000000 * 10**_decimals;

    uint256 public _maxTxAmount = 1000000 * 10**_decimals;
    uint256 public _maxWalletSize = 1000000 * 10**_decimals;
    uint256 public constant _taxSwapThreshold = 100000 * 10**_decimals;
    uint256 public constant _maxTaxSwap = 1000000 * 10**_decimals;

    uint256 private constant _initialBuyTax = 20;
    uint256 private constant _initialSellTax = 25;
    uint256 private constant _reduceBuyTaxAt = 30;
    uint256 private constant _reduceSellTaxAt = 45;
    uint256 private constant _preventSwapBefore = 40;
    uint256 private _finalBuyTax = 10;
    uint256 private _finalSellTax = 20;
    uint256 private _buyCount = 0;
    uint256 private countTax;

    uint256 public _dynamicTaxRate;
    uint256 public _volumeThreshold = 500000 * 10**_decimals;
    uint256 public _volumeCounter = 0;
    uint256 public _adjustmentFactor = 5; // Adjust tax by 5% when volume threshold is crossed

    uint256 public _liquidityThreshold = 200000 * 10**_decimals;
    bool private _autoAddLiquidity = false;

    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;

    event FinalTax(uint256 _valueBuy, uint256 _valueSell);
    event TradingActive(bool _tradingOpen, bool _swapEnabled);
    event maxAmount(uint256 _value);
    event SwapAndLiquify(uint256 half, uint256 newBalance, uint256 otherHalf);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor (address taxWallet) {
         _taxWallet = payable (taxWallet);
        _balances[_msgSender()] = _totalSupply;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[_taxWallet] = true;
        _isExcludedFromFee[address(this)] = true;
        
        emit Transfer(address(0), _msgSender(), _totalSupply);
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
        return _totalSupply;
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
        require(_allowances[sender][_msgSender()] >= amount, "ERC20: transfer amount exceeds allowance");
        _allowances[sender][_msgSender()] -= amount;
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0) && spender != address(0), "ERC20: approve the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

        function isExcludedFromFee(address account) public view returns (bool) {
        return _isExcludedFromFee[account];
    }

    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0) && to != address(0), "ERC20: transfer the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount=0;

        if (from != owner() && to != owner()) { 

            if(!tradingOpen ){
                require(_isExcludedFromFee[to] || _isExcludedFromFee[from],
                "trading not yet open"
                );
            }

            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _isExcludedFromFee[to] ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
                _buyCount++;
            }
            
            if (to == uniswapV2Pair && from != address(this)) {
                taxAmount = amount * ((_buyCount > _reduceSellTaxAt) ? _finalSellTax : _initialSellTax) / 100;    
            } 
            else if (from == uniswapV2Pair && to != address(this)) {
                taxAmount = amount * ((_buyCount > _reduceBuyTaxAt) ? _finalBuyTax : _initialBuyTax) / 100;
            }

            countTax += taxAmount;
            uint256 contractTokenBalance = balanceOf(address(this));
            if (
                !inSwap && 
                to == uniswapV2Pair && 
                swapEnabled && 
                contractTokenBalance>_taxSwapThreshold && 
                _buyCount>_preventSwapBefore &&
                countTax > _taxSwapThreshold / 2
            ){
                countTax = 0;
                uint256 getMinValue = (contractTokenBalance > _maxTaxSwap)?_maxTaxSwap:contractTokenBalance;
                swapTokensForEth((amount>getMinValue)?getMinValue:amount);
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        if(taxAmount > 0){
            _balances[address(this)] += taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }
        require(_balances[from] >= amount, "ERC20: transfer amount exceeds balance");
        _balances[from] -= amount;
        _balances[to] += (amount - taxAmount);
        emit Transfer(from, to, amount - taxAmount);
    }

    function sendETHToFee(uint256 amount) private {
        _taxWallet.transfer(amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function initialize () external onlyOwner {
        require(!tradingOpen,"init already called");
        uint256 tokenAmount = balanceOf(address(this)) - (_totalSupply * _initialBuyTax / 100);
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH()
        );
        uniswapV2Router.addLiquidityETH{value: address(this).balance} (
            address(this),
            tokenAmount,
            0,
            0,
            _msgSender(),
            block.timestamp
        );
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max); 
    }

    function activateTrading() external onlyOwner {
        require(!tradingOpen,"trading already open");
        swapEnabled = true;
        tradingOpen = true;
        emit TradingActive (tradingOpen, swapEnabled);
    }

    function configureTaxRates(uint256 _valueBuy, uint256 _valueSell) external onlyOwner {
        require(_valueBuy <= 30 && _valueSell <= 30 && tradingOpen, "Exceeds value");
        _finalBuyTax = _valueBuy;
        _finalSellTax = _valueSell;
        emit FinalTax(_valueBuy, _valueSell);
    }

    function changeFeeCollector(address payable newTaxWallet) external onlyOwner {
        require(newTaxWallet != address(0), "Zero address not allowed");
        _taxWallet = newTaxWallet;
    }

    function updateMaxTransactionLimit(uint256 newMaxTxAmount) external onlyOwner {
        _maxTxAmount = newMaxTxAmount;
    }

    function updateMaxWalletHoldings(uint256 newMaxWalletSize) external onlyOwner {
        _maxWalletSize = newMaxWalletSize;
    }

    function eliminateTransactionRestrictions() external onlyOwner {
        _maxTxAmount = _totalSupply;
        _maxWalletSize = _totalSupply;
        emit maxAmount(_totalSupply);
    }

    receive() external payable {}
}