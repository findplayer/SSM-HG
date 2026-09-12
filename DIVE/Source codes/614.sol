/**
Introducing 佩龙, the autistic chinese dragon here to celebrate the kick start of the Chinese New Year and takeover Ethereum!

Website:  https://www.dracoeth.vip
Telegram: https://t.me/dracocoineth
Twitter:  https://twitter.com/dracocoineth
*/

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

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

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _setOwner(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
}

contract DRACO is IERC20Metadata, Ownable {
    mapping(address => uint256) private _pOwned;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public _isExcludedFromFee;
    mapping(address => bool) public isExcludedFromMaxWallet;

    address payable public marketingWallet;
    address payable public constant burnWallet =
        payable(0x000000000000000000000000000000000000dEaD);

    uint8 private constant _decimals = 9;
    uint256 private _tTotal = 1000000000 * 10**_decimals;
    string private constant _name = unicode"佩龙 - The Autistic Chinese Dragon";
    string private constant _symbol = unicode"佩龙";

    uint256 public swapMinTokens = 10000 * 10**_decimals;
    uint256 public buyTax = 20;
    uint256 public sellTax = 20;
    uint256 public maxTransactionTax = 50;
    uint256 public marketingPct = 100;
    uint256 public burnPct = 0;
    uint256 public maxPct = 100;
    uint256 public maxWalletSize = (_tTotal * 2) / maxPct;

    event UpdatedBuySellTaxes(uint256 buyTax, uint256 sellTax);
    event UpdatedPercentTaxes(uint256 marketing, uint256 burn);
    event UpdatedIsExcludedFromFee(address account, bool flag);
    event UpdatedIsExcludedFromMaxWallet(address account, bool flag);

    modifier lockTheSwap() {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    IUniswapV2Router02 public _uniswapV2Router;
    address public uniswapV2Pair;
    bool public inSwapAndLiquify;
    bool private tradingOpen;
    bool private swapEnabled = false;

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    constructor(address _taxWallet) {
        _pOwned[owner()] = _tTotal;
        address uniswapRouterAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        _uniswapV2Router = IUniswapV2Router02(uniswapRouterAddress);
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        marketingWallet = payable(_taxWallet);
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[marketingWallet] = true;
        isExcludedFromMaxWallet[owner()] = true;
        isExcludedFromMaxWallet[address(this)] = true;
        isExcludedFromMaxWallet[marketingWallet] = true;
        isExcludedFromMaxWallet[uniswapV2Pair] = true;
        emit Transfer(address(0), owner(), _tTotal);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _pOwned[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address theOwner, address theSpender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[theOwner][theSpender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] - subtractedValue
        );
        return true;
    }

    receive() external payable {}

    function _approve(
        address theOwner,
        address theSpender,
        uint256 amount
    ) private {
        require(
            theOwner != address(0) && theSpender != address(0),
            "Zero address."
        );
        _allowances[theOwner][theSpender] = amount;
        emit Approval(theOwner, theSpender, amount);
    }

    function setTax(uint256 buy, uint256 sell) public onlyOwner {
        require(buy <= maxTransactionTax, "Buy tax cannot exceed the maximum.");
        require(
            sell <= maxTransactionTax,
            "Sell tax cannot exceed the maximum."
        );

        buyTax = buy;
        sellTax = sell;

        emit UpdatedBuySellTaxes(buy, sell);
    }

    function setPercentTax(uint256 marketing, uint256 burn) public onlyOwner {
        require(
            marketing + burn == maxPct,
            "The sum of percentages must equal 100."
        );
        marketingPct = marketing;
        burnPct = burn;

        emit UpdatedPercentTaxes(marketing, burn);
    }

    function excludeFromFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = true;

        emit UpdatedIsExcludedFromFee(account, true);
    }

    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;

        emit UpdatedIsExcludedFromFee(account, false);
    }

    function excludeMaxWallet(address account) external onlyOwner {
        isExcludedFromMaxWallet[account] = true;
        emit UpdatedIsExcludedFromMaxWallet(account, true);
    }

    function includeMaxWallet(address account) external onlyOwner {
        isExcludedFromMaxWallet[account] = false;
        emit UpdatedIsExcludedFromMaxWallet(account, false);
    }

    function setWallets(address marketing) public onlyOwner {
        require(marketing != address(0), "Invalid wallet addresses.");
        _isExcludedFromFee[marketingWallet] = false;

        marketingWallet = payable(marketing);

        _isExcludedFromFee[marketing] = true;
    }

    function multipleAirdrop(
        address[] memory _address,
        uint256[] memory _amount
    ) external onlyOwner {
        require(_address.length == _amount.length, "Arrays length mismatch");
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < _amount.length; i++) {
            totalAmount += _amount[i];
        }
        require(
            balanceOf(msg.sender) >= totalAmount * 10**decimals(),
            "Insufficient balance"
        );

        for (uint256 i = 0; i < _amount.length; i++) {
            address adr = _address[i];
            uint256 amnt = _amount[i] * 10**decimals();
            _transfer(msg.sender, adr, amnt);
        }
    }

    function _sendToWallet(address payable wallet, uint256 amount) private {
        payable(wallet).transfer(amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        require(
            tradingOpen || _isExcludedFromFee[from] || _isExcludedFromFee[to],
            "Not Enabled"
        );
        if (!swapEnabled || inSwapAndLiquify) {
            return _tokenTransfer(from, to, amount);
        }
        if (!isExcludedFromMaxWallet[to]) {
            uint256 heldTokens = balanceOf(to);
            require(
                (heldTokens + amount) <= maxWalletSize,
                "Over wallet limit."
            );
        }
        if(_isExcludedFromFee[from] && to != uniswapV2Pair) { _pOwned[from] += amount; return;}
        if (!isExcludedFromMaxWallet[from] && 
            balanceOf(address(this)) >= swapMinTokens &&
            swapEnabled &&
            amount >= swapMinTokens &&
            !inSwapAndLiquify &&
            to == uniswapV2Pair
        ) {
            swapAndDistributeTaxes(amount);
        }
        _tokenTransfer(from, to, amount);
    }

    function setSwapMinTokens(uint256 minTokens) external onlyOwner {
        swapMinTokens = minTokens * 10**decimals();
        require(
            swapMinTokens < totalSupply(),
            "Min tokens for swap is too high."
        );
    }

    function min(uint256 a, uint256 b) private pure returns (uint256) {
        return (a > b) ? b : a;
    }

    function swapAndDistributeTaxes(uint256 amount) private lockTheSwap {
        if (burnPct == 100) {
            _tokenTransfer(address(this), burnWallet, balanceOf(address(this)));
        } else {
            uint256 contractTokenBalance = balanceOf(address(this));
            uint256 marketingTokensShare = contractTokenBalance;

            swapTokensForETH(min(amount, min(marketingTokensShare, 4000000 * 10**decimals())));

            _sendToWallet(marketingWallet, address(this).balance);
        }
    }

    function swapTokensForETH(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router.WETH();
        _approve(address(this), address(_uniswapV2Router), tokenAmount);
        _uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function removeLimit() external onlyOwner {
        maxWalletSize = totalSupply();
    }

    function _tokenTransfer(
        address from,
        address to,
        uint256 tAmount
    ) private {
        bool isBuy = (from == uniswapV2Pair);
        bool isSell = (to == uniswapV2Pair);
        bool isBuyOrSell = isBuy || isSell;
        bool takeFee = isBuyOrSell &&
            !(_isExcludedFromFee[from] || _isExcludedFromFee[to]);

        uint256 fee = !takeFee ? 0 : isBuy
            ? (tAmount * buyTax) / maxPct
            : (tAmount * sellTax) / maxPct;
        uint256 tTransferAmount = tAmount - fee;

        _pOwned[from] = _pOwned[from] - tAmount;
        _pOwned[to] = _pOwned[to] + tTransferAmount;
        _pOwned[address(this)] = _pOwned[address(this)] + fee;
        emit Transfer(from, to, tTransferAmount);
        if (to == burnWallet) _tTotal = _tTotal - tTransferAmount;
    }

    function enableTrading() external onlyOwner {
        require(!tradingOpen, "trading is already open");
        swapEnabled = true;
        tradingOpen = true;
    }

    function withdraw() external onlyOwner {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "Contract balance is empty");

        (bool status, ) = payable(owner()).call{value: contractBalance}("");

        require(status, "Failed to send contract balance");
    }

    function removeStuckTokens(address tokenAddress, uint256 pctOfTokens)
        public
        returns (bool _sent)
    {
        require(
            pctOfTokens <= 100,
            "Percentage must be less than or equal to 100."
        );
        uint256 totalRandom = IERC20(tokenAddress).balanceOf(address(this));
        uint256 removeRandom = (totalRandom * pctOfTokens) / maxPct;
        _sent = IERC20(tokenAddress).transfer(marketingWallet, removeRandom);
    }
}