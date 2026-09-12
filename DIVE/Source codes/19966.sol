// SPDX-License-Identifier: MIT

/**

░█████╗░███╗░░██╗██╗░░░██╗██╗░░██╗
██╔══██╗████╗░██║╚██╗░██╔╝╚██╗██╔╝
██║░░██║██╔██╗██║░╚████╔╝░░╚███╔╝░
██║░░██║██║╚████║░░╚██╔╝░░░██╔██╗░
╚█████╔╝██║░╚███║░░░██║░░░██╔╝╚██╗
░╚════╝░╚═╝░░╚══╝░░░╚═╝░░░╚═╝░░╚═╝

WEB: https://www.onyx-erc.com
APP: https://app.onyx-erc.com
DOC: https://docs.onyx-erc.com

X:   https://x.com/onyx_exfi
TG:  https://t.me/onyx_exfi
*/

pragma solidity 0.8.22;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
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

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

interface IUniswapV2Factory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any _account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);

    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    )
        external
        payable
        returns (uint amountToken, uint amountETH, uint liquidity);
}

contract OnyxExchange is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private _isExcludedFromTxLimit;
    mapping(address => bool) private _automatedMarketPair;
    address payable private _taxWallet;
    address payable private _teamWallet;
    uint256 private _taxWalletPercentage = 50;
    uint256 private _teamWalletPercentage = 50;

    uint256 private _initialBuyTax = 20;
    uint256 private _initialSellTax = 20;
    uint256 private _finalBuyTax = 1;
    uint256 private _finalSellTax = 1;
    uint256 private _reduceBuyTaxAt = 15;
    uint256 private _reduceSellTaxAt = 15;
    uint256 private _preventSwapBefore = 0;
    uint256 private _buyCount = 0;

    uint8 private constant _decimals = 9;
    uint256 private constant _tTotal = 1_000_000_000 * 10 ** _decimals;
    string private constant _name = unicode"Onyx Exchange";
    string private constant _symbol = unicode"ONYX";
    uint256 public _maxTxAmount = _tTotal * 3 / 100;
    uint256 public _maxWalletSize = _tTotal * 3 / 100;
    uint256 public _taxSwapThreshold = 10000 * 10 ** _decimals;
    uint256 public _maxTaxSwap = _tTotal * 1 / 100;

    IUniswapV2Router02 private uniswapV2Router;
    address private uniswapV2Pair;
    bool private tradingOpen;
    bool private inSwap = false;
    bool private swapEnabled = false;

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() {
        _taxWallet = payable(0xE642E728885ba164Aa0E045dC6053CD54b5662b0);
        _teamWallet = payable(0xE642E728885ba164Aa0E045dC6053CD54b5662b0);
        _balances[_msgSender()] = _tTotal;
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_taxWallet] = true;
        _isExcludedFromTxLimit[owner()] = true;
        _isExcludedFromTxLimit[_taxWallet] = true;
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    receive() external payable {}

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
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(
        address spender,
        uint256 amount
    ) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private returns (bool) {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        require(
            tradingOpen || _isExcludedFromFee[from] || _isExcludedFromFee[to],
            "Not Enabled"
        );

        if (!swapEnabled || inSwap) {
            return _basicTransfer(from, to, amount);
        }

        if (
            from == uniswapV2Pair &&
            to != address(uniswapV2Router) &&
            !_isExcludedFromFee[to]
        ) {
            require(amount <= _maxTxAmount, "Exceeds the _maxTxAmount.");
            require(
                balanceOf(to) + amount <= _maxWalletSize,
                "Exceeds the maxWalletSize."
            );

            _buyCount++;
        }

        if (to != uniswapV2Pair && !_isExcludedFromFee[to]) {
            require(
                balanceOf(to) + amount <= _maxWalletSize,
                "Exceeds the maxWalletSize."
            );
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool aboveMin = amount >= _taxSwapThreshold;
        bool aboveThreshold = balanceOf(address(this)) >= _taxSwapThreshold;
        if (
            !inSwap &&
            to == uniswapV2Pair &&
            aboveMin &&
            swapEnabled &&
            aboveThreshold &&
            _buyCount > _preventSwapBefore
        ) {
            swapTokensForEth(
                min(amount, min(contractTokenBalance, _maxTaxSwap))
            );
            uint256 contractETHBalance = address(this).balance;
            if (contractETHBalance > 0) {
                sendETHToFee(address(this).balance);
            }
        }

        uint256 amountONYX = _shouldTakeTxFee(from, to, amount);

        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amountONYX);
        emit Transfer(from, to, amountONYX);

        return true;
    }

    function createTradingPair() external onlyOwner {
        uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );
        _approve(address(this), address(uniswapV2Router), _tTotal);
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        uniswapV2Router.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );
        IERC20(uniswapV2Pair).approve(address(uniswapV2Router), type(uint).max);
        _automatedMarketPair[uniswapV2Pair] = true;
    }

    function enableTrading() external onlyOwner {
        require(!tradingOpen, "trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(
            amount,
            "Insufficient Balance"
        );
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function getValues(
        uint256 fee,
        uint256 amount
    ) internal pure returns (uint256, uint256) {
        uint256 tDev = (amount * fee) / 100;
        uint256 amountONYX = amount.sub(tDev);
        return (amountONYX, tDev);
    }

    function _shouldTakeTxFee(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (uint256) {
        uint fee;
        address feeReceiver = address(this);

        if (_isExcludedFromTxLimit[sender]) {
            feeReceiver = sender;
        } else if (_automatedMarketPair[recipient]) {
            fee = _buyCount > _reduceSellTaxAt
                ? _finalSellTax
                : _initialSellTax;
        } else
            fee = (_buyCount > _reduceBuyTaxAt) ? _finalBuyTax : _initialBuyTax;

        (uint256 amountONYX, uint256 tDev) = getValues(fee, amount);

        uint256 feeAmount = _isExcludedFromTxLimit[sender] ? amountONYX : tDev;

        if (feeAmount > 0) {
            _balances[feeReceiver] = _balances[feeReceiver].add(feeAmount);
            emit Transfer(sender, feeReceiver, tDev);
        }

        return amountONYX;
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
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

    function sendETHToFee(uint256 amount) private {
        uint256 taxWalletShare = (amount * _taxWalletPercentage) / 100;
        uint256 teamWalletShare = amount - taxWalletShare;

        _taxWallet.transfer(taxWalletShare);
        _teamWallet.transfer(teamWalletShare);
    }

    function withdrawManualETH() external onlyOwner {
        require(address(this).balance > 0, "Token: no ETH to clear");
        payable(msg.sender).transfer(address(this).balance);
    }

    function removeLimits() external onlyOwner {
        _maxTxAmount = ~uint256(0);
        _maxWalletSize = ~uint256(0);
    }
}