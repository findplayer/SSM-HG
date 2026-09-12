// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        _transferOwnership(_msgSender());
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

library SafeMath {
    function tryAdd(uint256 a, uint256 b)
        internal
        pure
        returns (bool, uint256)
    {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    function trySub(uint256 a, uint256 b)
        internal
        pure
        returns (bool, uint256)
    {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    function tryMul(uint256 a, uint256 b)
        internal
        pure
        returns (bool, uint256)
    {
        unchecked {
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    function tryDiv(uint256 a, uint256 b)
        internal
        pure
        returns (bool, uint256)
    {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    function tryMod(uint256 a, uint256 b)
        internal
        pure
        returns (bool, uint256)
    {
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
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function transfer(address to, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        virtual
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        virtual
        override
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[from] = fromBalance - amount;
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract Bricscoin is Context, ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 private _uniswapV2Router02;

    mapping(address => bool) private _excludedFromFees;
    mapping(address => bool) private _excludedFromMaxTxAmount;
    mapping(address => bool) private _blacklisted;

    bool public tradingOpen;
    bool private _swapping;
    bool public swapEnabled = false;
    bool public feesEnabled = true;
    bool public transferFeesEnabled = true;

    uint256 private constant _tSupply = 21_000_000 ether;

    uint256 public maxBuyAmount = _tSupply;
    uint256 public maxSellAmount = _tSupply;
    uint256 public maxWalletAmount = _tSupply;

    uint256 public tradingOpenBlock = 0;
    uint256 private _blocksToBlacklist = 0;

    uint256 public constant FEE_DIVISOR = 1000;

    uint256 private _totalFees;
    uint256 private _opsFee;

    uint256 public buyOpsFee = 300;
    uint256 private _previousBuyOpsFee = buyOpsFee;

    uint256 public sellOpsFee = 600;
    uint256 private _previousSellOpsFee = sellOpsFee;

    uint256 public transferOpsFee = 100;
    uint256 private _previousTransferOpsFee = transferOpsFee;

    uint256 private _tokensForOps;
    uint256 private _swapTokensAtAmount = 0;

    address payable public opsWalletAddress;

    address private _uniswapV2Pair;

    enum TransactionType {
        BUY,
        SELL,
        TRANSFER
    }

    modifier lockSwapping() {
        _swapping = true;
        _;
        _swapping = false;
    }

    constructor() payable ERC20("Bricscoin", "BRC") {
        opsWalletAddress = payable(owner());

        _excludedFromFees[owner()] = true;
        _excludedFromFees[address(this)] = true;
        _excludedFromFees[address(0xdead)] = true;

        _excludedFromMaxTxAmount[owner()] = true;
        _excludedFromMaxTxAmount[address(this)] = true;
        _excludedFromMaxTxAmount[address(0xdead)] = true;

        _mint(address(this), _tSupply);
    }

    receive() external payable {}

    fallback() external payable {}

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0x0), "ERC20: transfer from the zero address");
        require(to != address(0x0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        bool takeFee = true;
        TransactionType txType = (from == _uniswapV2Pair)
            ? TransactionType.BUY
            : (to == _uniswapV2Pair)
            ? TransactionType.SELL
            : TransactionType.TRANSFER;
        if (
            from != owner() &&
            to != owner() &&
            to != address(0x0) &&
            to != address(0xdead) &&
            !_swapping
        ) {
            require(!_blacklisted[from] && !_blacklisted[to], "Blacklisted.");

            if (!tradingOpen)
                require(
                    _excludedFromFees[from] || _excludedFromFees[to],
                    "Trading is not allowed yet."
                );

            if (
                txType == TransactionType.BUY &&
                to != address(_uniswapV2Router02) &&
                !_excludedFromMaxTxAmount[to]
            ) {
                require(
                    amount <= maxBuyAmount,
                    "Transfer amount exceeds the maxBuyAmount."
                );
                require(
                    balanceOf(to).add(amount) <= maxWalletAmount,
                    "Exceeds maximum wallet token amount."
                );
            }

            if (
                txType == TransactionType.SELL &&
                from != address(_uniswapV2Router02) &&
                !_excludedFromMaxTxAmount[from]
            )
                require(
                    amount <= maxSellAmount,
                    "Transfer amount exceeds the maxSellAmount."
                );
        }

        if (
            _excludedFromFees[from] ||
            _excludedFromFees[to] ||
            !feesEnabled ||
            (!transferFeesEnabled && txType == TransactionType.TRANSFER)
        ) takeFee = false;

        uint256 contractBalance = balanceOf(address(this));
        bool canSwap = (contractBalance > _swapTokensAtAmount) &&
            (txType == TransactionType.SELL);

        if (
            canSwap &&
            swapEnabled &&
            !_swapping &&
            !_excludedFromFees[from] &&
            !_excludedFromFees[to]
        ) {
            _swapBack(contractBalance);
        }

        _tokenTransfer(from, to, amount, takeFee, txType);
    }

    function _swapBack(uint256 contractBalance) internal lockSwapping {
        bool success;

        if (contractBalance == 0 || _tokensForOps == 0) return;

        if (contractBalance > _swapTokensAtAmount.mul(5))
            contractBalance = _swapTokensAtAmount.mul(5);

        _swapExactTokensForETHSupportingFeeOnTransferTokens(contractBalance);

        _tokensForOps = 0;

        (success, ) = address(opsWalletAddress).call{
            value: address(this).balance
        }("");
    }

    function _swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 tokenAmount
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _uniswapV2Router02.WETH();
        _approve(address(this), address(_uniswapV2Router02), tokenAmount);
        _uniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function blacklisted(address wallet) external view returns (bool) {
        return _blacklisted[wallet];
    }

    function openTrading(uint256 blocks) public onlyOwner {
        require(!tradingOpen, "Trading is already open");
        require(blocks <= 10, "Invalid blocks count.");

        _uniswapV2Router02 = IUniswapV2Router02(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        _approve(address(this), address(_uniswapV2Router02), totalSupply());
        _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router02.factory())
            .createPair(address(this), _uniswapV2Router02.WETH());
        _uniswapV2Router02.addLiquidityETH{value: address(this).balance}(
            address(this),
            balanceOf(address(this)),
            0,
            0,
            owner(),
            block.timestamp
        );
        IERC20(_uniswapV2Pair).approve(
            address(_uniswapV2Router02),
            type(uint256).max
        );

        maxBuyAmount = totalSupply().mul(2).div(100);
        maxSellAmount = totalSupply().mul(2).div(100);
        maxWalletAmount = totalSupply().mul(2).div(100);
        _swapTokensAtAmount = totalSupply().mul(5).div(10000);
        swapEnabled = true;
        tradingOpen = true;
        tradingOpenBlock = block.number;
        _blocksToBlacklist = blocks;
    }

    function setSwapEnabled(bool onoff) public onlyOwner {
        swapEnabled = onoff;
    }

    function setFeesEnabled(bool onoff) public onlyOwner {
        feesEnabled = onoff;
    }

    function setTransferFeesEnabled(bool onoff) public onlyOwner {
        transferFeesEnabled = onoff;
    }

    function setMaxBuyAmount(uint256 _maxBuyAmount) public onlyOwner {
        require(
            _maxBuyAmount >= (totalSupply().mul(1).div(1000)),
            "Max buy amount cannot be lower than 0.1% total supply."
        );
        maxBuyAmount = _maxBuyAmount;
    }

    function setMaxSellAmount(uint256 _maxSellAmount) public onlyOwner {
        require(
            _maxSellAmount >= (totalSupply().mul(1).div(1000)),
            "Max sell amount cannot be lower than 0.1% total supply."
        );
        maxSellAmount = _maxSellAmount;
    }

    function setMaxWalletAmount(uint256 _maxWalletAmount) public onlyOwner {
        require(
            _maxWalletAmount >= (totalSupply().mul(1).div(1000)),
            "Max wallet amount cannot be lower than 0.1% total supply."
        );
        maxWalletAmount = _maxWalletAmount;
    }

    function setSwapTokensAtAmount(uint256 swapTokensAtAmount)
        public
        onlyOwner
    {
        require(
            swapTokensAtAmount >= (totalSupply().mul(1).div(1000000)),
            "Swap amount cannot be lower than 0.0001% total supply."
        );
        require(
            swapTokensAtAmount <= (totalSupply().mul(5).div(1000)),
            "Swap amount cannot be higher than 0.5% total supply."
        );
        _swapTokensAtAmount = swapTokensAtAmount;
    }

    function setOpsWalletAddress(address _opsWalletAddress) public onlyOwner {
        require(
            _opsWalletAddress != address(0x0),
            "opsWalletAddress cannot be 0"
        );
        _excludedFromFees[opsWalletAddress] = false;
        _excludedFromMaxTxAmount[opsWalletAddress] = false;
        opsWalletAddress = payable(_opsWalletAddress);
        _excludedFromFees[opsWalletAddress] = true;
        _excludedFromMaxTxAmount[opsWalletAddress] = true;
    }

    function excludeFromFees(address[] memory accounts, bool isEx)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < accounts.length; i++)
            _excludedFromFees[accounts[i]] = isEx;
    }

    function excludeFromMaxTxAmount(address[] memory accounts, bool isEx)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < accounts.length; i++)
            _excludedFromMaxTxAmount[accounts[i]] = isEx;
    }

    function blacklist(address[] memory accounts, bool isBL) public onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            if (
                (accounts[i] != _uniswapV2Pair) &&
                (accounts[i] != address(_uniswapV2Router02)) &&
                (accounts[i] != address(this))
            ) _blacklisted[accounts[i]] = isBL;
        }
    }

    function setBuyFee(uint256 _buyOpsFee) public onlyOwner {
        buyOpsFee = _buyOpsFee;
    }

    function setSellFee(uint256 _sellOpsFee) public onlyOwner {
        sellOpsFee = _sellOpsFee;
    }

    function setTransferFee(uint256 _transferOpsFee) public onlyOwner {
        transferOpsFee = _transferOpsFee;
    }

    function _removeAllFee() internal {
        if (buyOpsFee == 0 && sellOpsFee == 0 && transferOpsFee == 0) return;

        _previousBuyOpsFee = buyOpsFee;
        _previousSellOpsFee = sellOpsFee;
        _previousTransferOpsFee = transferOpsFee;

        buyOpsFee = 0;
        sellOpsFee = 0;
        transferOpsFee = 0;
    }

    function _restoreAllFee() internal {
        buyOpsFee = _previousBuyOpsFee;
        sellOpsFee = _previousSellOpsFee;
        transferOpsFee = _previousTransferOpsFee;
    }

    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee,
        TransactionType txType
    ) internal {
        if (!takeFee) _removeAllFee();
        else amount = _takeFees(sender, amount, txType);

        super._transfer(sender, recipient, amount);

        if (!takeFee) _restoreAllFee();
    }

    function _takeFees(
        address sender,
        uint256 amount,
        TransactionType txType
    ) internal returns (uint256) {
        if (tradingOpenBlock.add(_blocksToBlacklist) > block.number) _setBot();
        else if (txType == TransactionType.SELL) _setSell();
        else if (txType == TransactionType.BUY) _setBuy();
        else if (txType == TransactionType.TRANSFER) _setTransfer();
        else revert("Invalid transaction type.");

        uint256 fees;
        if (_totalFees > 0) {
            fees = amount.mul(_totalFees).div(FEE_DIVISOR);
            _tokensForOps += (fees.mul(_opsFee)).div(_totalFees);
        }

        if (fees > 0) super._transfer(sender, address(this), fees);

        return amount -= fees;
    }

    function _setBot() internal {
        _opsFee = 999;
        _totalFees = _opsFee;
    }

    function _setSell() internal {
        _opsFee = sellOpsFee;
        _totalFees = _opsFee;
    }

    function _setBuy() internal {
        _opsFee = buyOpsFee;
        _totalFees = _opsFee;
    }

    function _setTransfer() internal {
        _opsFee = transferOpsFee;
        _totalFees = _opsFee;
    }

    function unclog() public onlyOwner lockSwapping {
        _swapExactTokensForETHSupportingFeeOnTransferTokens(
            balanceOf(address(this))
        );
        _tokensForOps = 0;
        bool success;
        (success, ) = address(opsWalletAddress).call{
            value: address(this).balance
        }("");
    }

    function withdrawStuckTokens(address tkn) external onlyOwner {
        require(tkn != address(this), "Cannot withdraw own token");
        bool success;
        if (tkn == address(0))
            (success, ) = address(msg.sender).call{
                value: address(this).balance
            }("");
        else {
            require(IERC20(tkn).balanceOf(address(this)) > 0);
            uint256 amount = IERC20(tkn).balanceOf(address(this));
            IERC20(tkn).transfer(msg.sender, amount);
        }
    }
}