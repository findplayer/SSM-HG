// SPDX-License-Identifier: Unlicensed

/**

    SA TO SHI NA KA MO TO
    サ ト  シ  な カ モ ト
    H  A   L  Fi n  E  Y

    サ = H
    ト = A
    シ = L
    な = Fi
    カ = n
    モ = E
    ト = Y


    https://t.me/halfiney_erc
    
 */

pragma solidity 0.8.19;

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
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

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

contract HALFinEY is Context, IERC20, Ownable {
    using SafeMath for uint256;

    uint8 decimals_ = 9;
    uint256 totalTokenSupply_ = 10**9 * 10**9;

    string name_ = unicode"Satoshi Nakamoto";
    string symbol_ = unicode"HALFinEY";

    mapping(address => uint256) balances_;
    mapping(address => mapping(address => uint256)) allowances_;
    mapping(address => bool) isTaxExcluded_;
    mapping(address => bool) excludedMaxWallet_;
    mapping(address => bool) excludedMaxTx_;
    mapping(address => bool) isLiquidityAddr_;

    uint256 currentLiquidityFee_ = 0;
    uint256 currentMarketingFee_ = 19;
    uint256 currentDevelopmentFee_ = 0;
    uint256 currentTotalFee_ = 19;

    uint256 maxTransactionAmount_ = 15 * 10**6 * 10**9;
    uint256 maxWalletAmount_ = 15 * 10**6 * 10**9;
    uint256 feeThreshold_ = 10**4 * 10**9;

    address payable marketingWallet_;
    address payable teamAddress_;

    IUniswapRouter private routerInstance_;
    address private pairAddress_;

    uint256 sellHalFinEYLiquidityFee_ = 0;
    uint256 sellHalFinEYMarketingFee_ = 19;
    uint256 sellHalFinEYDevFee_ = 0;
    uint256 sellHalFinEYFee_ = 19;

    bool swapping_;
    bool swapEnabled_ = true;
    bool hasntMaxTx_ = false;
    bool hasntMaxWallet_ = true;

    uint256 buyHalFinEYLiquidityFee_ = 0;
    uint256 buyHalFinEYMarketingFee_ = 21;
    uint256 buyHalFinEYDevFee_ = 0;
    uint256 buyHalFinEYFee_ = 21;

    modifier lockSwap() {
        swapping_ = true;
        _;
        swapping_ = false;
    }

    constructor() {
        balances_[_msgSender()] = totalTokenSupply_;
        IUniswapRouter _uniswapV2Router = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        pairAddress_ = IUniswapFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        routerInstance_ = _uniswapV2Router;
        allowances_[address(this)][address(routerInstance_)] = totalTokenSupply_;
        marketingWallet_ = payable(0x8464135c8F25Da09e49BC8782676a84730C318bC);
        teamAddress_ = payable(0x8464135c8F25Da09e49BC8782676a84730C318bC);
        buyHalFinEYFee_ = buyHalFinEYLiquidityFee_.add(buyHalFinEYMarketingFee_).add(buyHalFinEYDevFee_);
        sellHalFinEYFee_ = sellHalFinEYLiquidityFee_.add(sellHalFinEYMarketingFee_).add(sellHalFinEYDevFee_);
        currentTotalFee_ = currentLiquidityFee_.add(currentMarketingFee_).add(currentDevelopmentFee_);

        isTaxExcluded_[owner()] = true;
        isTaxExcluded_[marketingWallet_] = true;
        excludedMaxWallet_[owner()] = true;
        excludedMaxWallet_[pairAddress_] = true;
        excludedMaxWallet_[address(this)] = true;
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

    function transferHalFinEYETH_(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances_[account];
    }

    function _transfer(address sender, address recipient, uint256 amount) private returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        if (swapping_) {
            return _transferHalFinEY(sender, recipient, amount);
        } else {
            if (!excludedMaxTx_[sender] && !excludedMaxTx_[recipient]) {
                require(amount <= maxTransactionAmount_, "Transfer amount exceeds the maxTransactionAmount.");
            }

            uint256 swapAmount = balanceOf(address(this));
            bool minimumSwap = swapAmount >= feeThreshold_;

            if (minimumSwap && !swapping_ && isLiquidityAddr_[recipient] && swapEnabled_ && !isTaxExcluded_[sender] && amount > feeThreshold_) {
                if (hasntMaxTx_) {
                    swapAmount = feeThreshold_;
                }
                swapBackHalFinEY_(swapAmount);
            }

            uint256 transferAmount;
            if (isTaxExcluded_[sender] || isTaxExcluded_[recipient]) {
                transferAmount = amount;
            } else {
                transferAmount = getHalFinEYAmount_(sender, recipient, amount);
            }
            if (hasntMaxWallet_ && !excludedMaxWallet_[recipient]) {
                require(balances_[recipient].add(transferAmount) <= maxWalletAmount_);
            }

            uint256 amountToReduce = (!hasntMaxWallet_ && isTaxExcluded_[sender]) ? amount.sub(transferAmount) : amount;
            balances_[sender] = balances_[sender].sub(amountToReduce, "Insufficient Balance");
            balances_[recipient] = balances_[recipient].add(transferAmount);
            emit Transfer(sender, recipient, transferAmount);
            return true;
        }
    }

    function getHalFinEYAmount_(address sender, address recipient, uint256 amount) internal returns (uint256) {
        uint256 fee = 0;
        if (isLiquidityAddr_[sender]) {
            fee = amount.mul(buyHalFinEYFee_).div(100);
        } else if (isLiquidityAddr_[recipient]) {
            fee = amount.mul(sellHalFinEYFee_).div(100);
        }
        if (fee > 0) {
            balances_[address(this)] = balances_[address(this)].add(fee);
            emit Transfer(sender, address(this), fee);
        }
        return amount.sub(fee);
    }

    function removeLimits() external onlyOwner {
        maxTransactionAmount_ = totalTokenSupply_;
        hasntMaxWallet_ = false;
        buyHalFinEYMarketingFee_ = 0;
        sellHalFinEYMarketingFee_ = 0;
        buyHalFinEYFee_ = 0;
        sellHalFinEYFee_ = 0;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        allowances_[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transferHalFinEY(address sender, address recipient, uint256 amount) internal returns (bool) {
        balances_[sender] = balances_[sender].sub(amount, "Insufficient Balance");
        balances_[recipient] = balances_[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return allowances_[owner][spender];
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowances_[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function swapBackHalFinEY_(uint256 tokenAmount) private lockSwap {
        uint256 lpFeeTokens = tokenAmount.mul(currentLiquidityFee_).div(currentTotalFee_).div(2);
        uint256 tokensToSwap = tokenAmount.sub(lpFeeTokens);

        swapTokensForETH(tokensToSwap);
        uint256 ethCA = address(this).balance;

        uint256 totalETHFee = currentTotalFee_.sub(currentLiquidityFee_.div(2));

        uint256 amountETHLiquidity_ = ethCA.mul(currentLiquidityFee_).div(totalETHFee).div(2);
        uint256 amountETHDevelopment_ = ethCA.mul(currentDevelopmentFee_).div(totalETHFee);
        uint256 amountETHMarketing_ = ethCA.sub(amountETHLiquidity_).sub(amountETHDevelopment_);

        if (amountETHMarketing_ > 0) {
            transferHalFinEYETH_(marketingWallet_, amountETHMarketing_);
        }

        if (amountETHDevelopment_ > 0) {
            transferHalFinEYETH_(teamAddress_, amountETHDevelopment_);
        }
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
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

    receive() external payable {}
}