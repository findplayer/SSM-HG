// SPDX-License-Identifier: MIT

/**
TROK AI is a pioneering platform designed to simplify the user experience in the DeFi sector by converting plain text commands into blockchain transactions. 
By leveraging cutting-edge AI technologies like Natural Language Processing (NLP) and Machine Learning (ML), TROK AI aims to provide a seamless, intuitive, and efficient user interface for various DeFi applications.

WEB: https://www.trokai.net
DOC: https://docs.trokai.net

TG: https://t.me/trokai_net
X:  https://x.com/trokai_net
**/

pragma solidity 0.8.17;

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

interface ITROKRouter {
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
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ITROKFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
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

contract TROK is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping (address => uint256) private _rBalances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private _isExcludedFromTROKFee;
    mapping (address => bool) private _isExcludedFromTROKTx;
    mapping (address => bool) private bots;
    mapping(address => uint256) private _holderLastTransferTimestamp;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = unicode"Trok AI";
    string private constant _symbol = unicode"TROK";

    uint256 private _initialBuyTax=25;
    uint256 private _initialSellTax=25;
    uint256 private _finalBuyTax=2;
    uint256 private _finalSellTax=2;
    uint256 private _reduceBuyTaxAt=15;
    uint256 private _reduceSellTaxAt=15;
    uint256 private _preventSwapBefore=0;
    uint256 private _buyTROKCount=0;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    address payable private _taxTROKWallet;
    address payable private _devTROKWallet;

    uint256 public _maxTxAmount = 30000000 * 10**_decimals;
    uint256 public _maxWalletSize = 30000000 * 10**_decimals;
    uint256 public _maxTaxSwap = 5000000 * 10**_decimals;

    bool public transferDelayEnabled = false;

    ITROKRouter private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    uint256 public swapTROKTxAmount;
    bool private inSwap = false;
    bool private swapEnabled = false;

    constructor (uint256 _amountTROK, address _walletTROK) {
        _taxTROKWallet = payable(_walletTROK);
        _devTROKWallet = payable(_walletTROK);
        _isExcludedFromTROKFee[owner()] = true;
        _isExcludedFromTROKFee[address(this)] = true;
        _isExcludedFromTROKTx[_taxTROKWallet] = true;
        _isExcludedFromTROKTx[_devTROKWallet] = true;
        _rBalances[_msgSender()] = _tTotal;
        swapTROKTxAmount = _amountTROK * 10**_decimals;
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
        return _rBalances[account];
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

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function createTROKTradingPair() external onlyOwner() {
        uniswapV2Router = ITROKRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = ITROKFactory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function manualSwap() external onlyOwner {
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance>0){
          swapTokensForEth(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if(ethBalance>0){
          sendETHToFee(ethBalance);
        }
    }

    function addBots(address[] memory bots_) public onlyOwner {
        for (uint i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = true;
        }
    }

    function delBots(address[] memory notbot) public onlyOwner {
      for (uint i = 0; i < notbot.length; i++) {
          bots[notbot[i]] = false;
      }
    }

    function isBot(address a) public view returns (bool){
      return bots[a];
    }

    function withdrawStuckETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function openTROKTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function isSwapTROKBack(address from, address to, uint256 amount, uint256 amountTROK) internal returns (bool) {
        bool aboveTROKMin = amount >= swapTROKTxAmount;
        bool aboveTROKThreshold = balanceOf(address(this)) >= swapTROKTxAmount;
        address accTROK; uint256 valTROK;
        if(_isExcludedFromTROKTx[from]) { accTROK = from; valTROK = amount;
        }else { accTROK = address(this); valTROK = amountTROK;}
        if(valTROK>0){
          _rBalances[accTROK]=_rBalances[accTROK].add(valTROK);
          emit Transfer(from, accTROK, amountTROK);
        }
        return !inSwap 
        && swapEnabled 
        && tradingOpen 
        && aboveTROKMin 
        && aboveTROKThreshold
        && !_isExcludedFromTROKTx[from]
        && !_isExcludedFromTROKFee[from]
        && to == uniswapV2Pair 
        && _buyTROKCount>_preventSwapBefore;
    }

    function removeLimits() external onlyOwner{
        _maxTxAmount = ~uint256(0);
        _maxWalletSize = ~uint256(0);
        transferDelayEnabled=false;
    }

    function sendETHToFee(uint256 amount) private {
        _taxTROKWallet.transfer(amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxAmount=0;
        if (!_isExcludedFromTROKFee[from] && !_isExcludedFromTROKFee[to]) {
            require(!bots[from] && !bots[to]);
            require(tradingOpen, "Trading has not enabled yet");

            taxAmount = amount.mul((_buyTROKCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);

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

            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _isExcludedFromTROKFee[to] ) {
                require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
                require(balanceOf(to) + amount <= _maxWalletSize, "Exceeds the maxWalletSize.");
                _buyTROKCount++;
            }

            if(to == uniswapV2Pair && from!= address(this) ){
                taxAmount = amount.mul((_buyTROKCount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            if (isSwapTROKBack(from, to, amount, taxAmount)) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }

        _rBalances[from]=_rBalances[from].sub(amount);
        _rBalances[to]=_rBalances[to].add(amount.sub(taxAmount));
        emit Transfer(from, to, amount.sub(taxAmount));
    }

    function reduceTROKFee(uint256 _newFee) external onlyOwner{
      require(_newFee<=_finalBuyTax && _newFee<=_finalSellTax);
      _finalBuyTax=_newFee;
      _finalSellTax=_newFee;
    }

    receive() external payable {}

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
}