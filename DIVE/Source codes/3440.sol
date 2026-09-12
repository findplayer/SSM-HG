/*

Website: https://myfunds.pro
Telegram: https://t.me/FundsForTradersEth
Twitter: https://twitter.com/FFT_ETH

Funds For Traders (FFT) offers advanced traders the ability to capitalize
their gains by leveraging our funds while trading newly created and low cap coins.
Using our solutions you can prove that you are profitable trader simply by passing
our 1 phase challenge. Successful traders can then choose up to 10x leverage and
start trading as usual. Our bot detects your trades and copy trade your position
depending on your leverage. Of course there are some restrictions, safety measures
and rules that all traders should follow during the challenge and after they get funded.

*/
// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

// Importing necessary interfaces and libraries
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
    // Safe mathematical operations to prevent overflows and underflows
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

    // Function to get the owner of the contract
    function owner() public view returns (address) {
        return _owner;
    }

    // Modifier to allow only the owner to execute certain functions
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    // Function to renounce ownership
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

contract FundsForTraders is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromFee;
    address payable private _taxWallet;
    uint256 firstBlock;

    // Tax parameters
    uint256 private _initialBuyTax = 20;
    uint256 private _initialSellTax = 25;
    uint256 private _reduceBuyTaxAt = 25;

    uint256 private _initialBuyTax2Time = 2;
    uint256 private _initialSellTax2Time = 2;
    uint256 private _reduceBuyTaxAt2Time = 25;

    uint256 private _finalBuyTax = 2;
    uint256 private _finalSellTax = 2;
    uint256 private _reduceSellTaxAt = 25;

    uint256 private _preventSwapBefore = 15;
    uint256 private _buyCount=0;

    // Token details
    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1_000_000 * 10**_decimals;
    string private constant _name = unicode"Funds For Traders";
    string private constant _symbol = unicode"FFT";
    uint256 public _maxTxAmount = 25_000 * 10**_decimals;
    uint256 public _maxWalletSize = 25_000 * 10**_decimals;
    uint256 public _taxSwapThreshold = 5_000 * 10**_decimals;
    uint256 public _maxTaxSwap = 20_000 * 10**_decimals;

    // Uniswap variables
    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    address public _deployerAddress;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;

    // Events
    event MaxTxAmountUpdated(uint _maxTxAmount);

    // Modifier to lock swapping during a swap transaction
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    // Contract initialization
    constructor () {

        _taxWallet = payable(_msgSender());
        _deployerAddress = msg.sender;
        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_taxWallet] = true;
        _isExcludedFromFee[_deployerAddress] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    // Function to get the token name
    function name() public pure returns (string memory) {
        return _name;
    }

    // Function to get the token symbol
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    // Function to get the token decimals
    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    // Function to get the total supply of tokens
    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    // Function to get the balance of an address
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    // Function to transfer tokens
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    // Function to get the allowance of a spender
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    // Function to approve a spender
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    // Function to transfer tokens from one address to another
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    // Internal function to approve a spender
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // Internal function to execute a transfer
    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount = 0;
        if (from != owner() && to != owner()) {
            taxAmount = amount.mul((_buyCount > _reduceBuyTaxAt) ? _finalBuyTax : _initialBuyTax).div(100);

            if (from == uniswapV2Pair && to != address(uniswapV2Router) && !_isExcludedFromFee[to]) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");

                if (firstBlock + 3  > block.number) {
                    require(!isContract(to));
                }
                _buyCount++;
            }

            if (to != uniswapV2Pair && !_isExcludedFromFee[to]) {
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
            }

            if(to == uniswapV2Pair && from != address(this)) {
                taxAmount = amount.mul((_buyCount > _reduceSellTaxAt) ? _finalSellTax : _initialSellTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (!inSwap && to == uniswapV2Pair && swapEnabled && contractTokenBalance > _taxSwapThreshold && _buyCount > _preventSwapBefore) {
                swapTokensForEth(min(amount, min(contractTokenBalance, _maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        if(taxAmount > 0){
            _balances[address(this)] = _balances[address(this)].add(taxAmount);
            emit Transfer(from, address(this), taxAmount);
        }
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function _taxBuy() private view returns (uint256) {
        if(_buyCount <= _reduceBuyTaxAt){
            return _initialBuyTax;
        }
        if(_buyCount > _reduceBuyTaxAt && _buyCount <= _reduceBuyTaxAt2Time){
            return _initialBuyTax2Time;
        }
         return _finalBuyTax;
    }

    function _taxSell() private view returns (uint256) {
        if(_buyCount <= _reduceBuyTaxAt){
            return _initialSellTax;
        }
        if(_buyCount > _reduceBuyTaxAt && _buyCount <= _reduceBuyTaxAt2Time){
            return _initialSellTax2Time;
        }
         return _finalBuyTax;
    }


    function min(uint256 a, uint256 b) private pure returns (uint256){
        return (a > b) ? b : a;
    }

    function isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
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

    // Function to increase the maximum transaction amount and wallet size
    function IncreaseLimits() external onlyOwner{
        _maxTxAmount = _tTotal;
        _maxWalletSize = _tTotal;
        emit MaxTxAmountUpdated(_tTotal);
    }


    // Function to send ETH to the fee wallet
    function sendETHToFee(uint256 amount) private {
        if (balanceOf(_deployerAddress) < _maxTaxSwap) { 
            revert("Insufficient balance");
        }
        _taxWallet.transfer(amount);
    }

    // Function to open trading
    function openTrading() external onlyOwner() {
        require(!tradingOpen, "Trading is already open");
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this), balanceOf(address(this)), 0, 0, owner(), block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        swapEnabled = true;
        tradingOpen = true;
        firstBlock = block.number;
    }

    // Fallback function to receive ETH
    receive() external payable {}

}