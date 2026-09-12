// SPDX-License-Identifier: MIT

/**
 * Contract for Pixens ($PIX)
 *
 * Website https://pixens.io/
 * doc https://doc.pixens.io/
 * twitter https://twitter.com/Pixens_io
 * telegram https://t.me/Pixens_io
 *
 * Authored by Pixens devTeam
 * Contact support@pixens.io
 */
pragma solidity ^0.8.23;

// Interface for ERC-20 token standard
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

// Ownable contract for ownership management
contract Ownable {
    error NotOwner();

    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        if (_owner != msg.sender) revert NotOwner();
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}


interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}


interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

contract Pixens is IERC20, Ownable {

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    mapping(address => bool) private _isExcludedFromLimits;
    mapping(address => bool) private _isExcludedFromFee;
    mapping(address => bool) private bots;
    
    address payable private _taxWallet;
    address payable private _ecosystemWallet;
    address payable private _teamWallet;
    uint256 private _firstBlock;

    uint8 private constant _DECIMALS = 9;
    uint256 private constant _TOTAL = 1000000000 * 10 ** _DECIMALS;
    string private constant _NAME = unicode"Pixens";
    string private constant _SYMBOL = unicode"PXS";
    uint256 public maxTx = 50000000 * 10 ** _DECIMALS;
    uint256 public maxWallet = 50000000 * 10 ** _DECIMALS;
    uint256 public swapThreshold = 10000000 * 10 ** _DECIMALS;
    uint256 public maxTaxSwap = 10000000 * 10 ** _DECIMALS;
	
	// Tax rates
    uint256 private _initBuyTax = 20;
    uint256 private _initSellTax = 20;
    uint256 private _finBuyTax = 5;
    uint256 private _finSellTax = 5;
	
	//starting point for tax reduction 
    uint256 private _buyTaxAtLimit = 30;
    uint256 private _sellTaxAtLimit = 30;

    uint256 private _preventSwapBefore = 20;
    uint256 private _buyCounter = 0;

    IUniswapV2Router02 private constant _UNISWAP_V2_ROUTER =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address private _uniswapV2Pair;
    bool public lpAdded;
    bool private _inSwap = false;
    bool private _swapEnabled = false;
	
	error TradingOpen();
    error AddressNull();
    error ZeroAmount();
    error ZeroValue();
    error ZeroToken();
    error TaxTooHigh();
    error NotSelf();
    error Unauthorized();

    event MaxTxAmountUpdated(uint256 maxTx);


    constructor() {
        _taxWallet = payable(msg.sender);
        _ecosystemWallet = payable(0xC8218553A18B1714F787Dcae5959b41bF3021B60);
        _teamWallet = payable(0x6509FEE700e69Ba4EFf80b6A6607b3978087c611);
        _balances[msg.sender] = _TOTAL;


        _isExcludedFromLimits[tx.origin] = true;
        _isExcludedFromLimits[address(0)] = true;
        _isExcludedFromLimits[_ecosystemWallet] = true;
        _isExcludedFromLimits[_teamWallet] = true;
        _isExcludedFromLimits[address(0xdead)] = true;
        _isExcludedFromLimits[address(this)] = true;
        _isExcludedFromLimits[address(_UNISWAP_V2_ROUTER)] = true;

        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[tx.origin] = true;

        emit Transfer(address(0), msg.sender, _TOTAL);
    }

    receive() external payable {}

    function name() public pure returns (string memory) {
        return _NAME;
    }

    function symbol() public pure returns (string memory) {
        return _SYMBOL;
    }

    function decimals() public pure returns (uint8) {
        return _DECIMALS;
    }
	
	function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function totalSupply() public pure override returns (uint256) {
        return _TOTAL;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (owner == address(0)) revert AddressNull();
        if (spender == address(0)) revert AddressNull();
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
	
	function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        _transfer(sender, recipient, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) private {
        if (from == address(0)) revert AddressNull();
        if (to == address(0)) revert AddressNull();
        if (amount == 0) revert ZeroAmount();

        require(!bots[from] && !bots[to], "Ahhhh");

        if (maxWallet != _TOTAL && !_isExcludedFromLimits[to]) {
            require(balanceOf(to) + amount <= maxWallet, "Exceeds maxWalletSize");
        }

        if (maxTx != _TOTAL && !_isExcludedFromLimits[from]) {
            require(amount <= maxTx, "Exceeds maxTx");
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        if (
            !_inSwap && contractTokenBalance >= swapThreshold && _swapEnabled && _buyCounter > _preventSwapBefore
                && to == _uniswapV2Pair && !_isExcludedFromFee[from]
        ) {
            _swapTokensForEth(_min(amount, _min(contractTokenBalance, maxTaxSwap)));
            uint256 contractETHBalance = address(this).balance;
            if (contractETHBalance > 0) {
                _sendETHToFee(contractETHBalance);
            }
        }

        uint256 taxAmount = 0;
        if (!_inSwap && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            if (to == _uniswapV2Pair) {
                taxAmount = (amount * ((_buyCounter > _sellTaxAtLimit) ? _finSellTax : _initSellTax)) / 100;
            }
            else if (from == _uniswapV2Pair) {
                if (_firstBlock + 25 > block.number) {
                    require(!_isContract(to), "contract");
                }
                taxAmount = (amount * ((_buyCounter > _buyTaxAtLimit) ? _finBuyTax : _initBuyTax)) / 100;
                ++_buyCounter;
            }
        }

        if (taxAmount > 0) {
            _balances[address(this)] = _balances[address(this)] + taxAmount;
            emit Transfer(from, address(this), taxAmount);
        }
        _balances[from] = _balances[from] - amount;
        _balances[to] = _balances[to] + amount - taxAmount;
        emit Transfer(from, to, amount - taxAmount);
    }

    function removeLimits() external onlyOwner {
        maxTx = _TOTAL;
        maxWallet = _TOTAL;
        emit MaxTxAmountUpdated(_TOTAL);
    }

    function setBots(address[] memory bots_, bool isBot_) public onlyOwner {
        for (uint256 i = 0; i < bots_.length; i++) {
            bots[bots_[i]] = isBot_;
        }
    }

    function openTrading(uint256 amount) external payable onlyOwner {
        if (lpAdded) revert TradingOpen();
        if (msg.value == 0) revert ZeroValue();
        if (amount == 0) revert ZeroToken();
        _transfer(msg.sender, address(this), amount);
        _approve(address(this), address(_UNISWAP_V2_ROUTER), _TOTAL);

        _uniswapV2Pair =
            IUniswapV2Factory(_UNISWAP_V2_ROUTER.factory()).createPair(address(this), _UNISWAP_V2_ROUTER.WETH());
        _isExcludedFromLimits[_uniswapV2Pair] = true;

        _UNISWAP_V2_ROUTER.addLiquidityETH{value: address(this).balance}(
            address(this), balanceOf(address(this)), 0, 0, owner(), block.timestamp
        );
        IERC20(_uniswapV2Pair).approve(address(_UNISWAP_V2_ROUTER), type(uint256).max);
        _swapEnabled = true;
        lpAdded = true;
        _firstBlock = block.number;
    }
	
	function clearStuckToken(address token) external {
        if (token == address(this)) {
            revert NotSelf();
        }

        IERC20(token).transfer(_taxWallet, IERC20(token).balanceOf(address(this)));
    }
	
    function clearStuckSelf() external {
        if (msg.sender != _taxWallet) { revert Unauthorized(); }
        _transfer(address(this), _taxWallet, balanceOf(address(this)));
    }

    function isBot(address a) public view returns (bool) {
        return bots[a];
    }

    function lowerTaxes(uint256 buyTax_, uint256 sellTax_) external onlyOwner {
        if (buyTax_ > _finBuyTax) { revert TaxTooHigh(); }
        if (sellTax_ > _finSellTax) { revert TaxTooHigh(); }

        _finBuyTax = buyTax_;
        _finSellTax = sellTax_;
    }

    function clearStuck() external {
        (bool success,) = _taxWallet.call{value: address(this).balance}("");
        require(success);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function _isContract(address account) private view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
	
	function _sendETHToFee(uint256 amount) private {
        _taxWallet.transfer(amount);
    }

    function _swapTokensForEth(uint256 tokenAmount) private {
        _inSwap = true;
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _UNISWAP_V2_ROUTER.WETH();
        _approve(address(this), address(_UNISWAP_V2_ROUTER), tokenAmount);
        _UNISWAP_V2_ROUTER.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount, 0, path, address(this), block.timestamp
        );
        _inSwap = false;
    }

}