// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

/* @title The Intellective Collective 
 * More info at: https://www.intellexuscollective.com
 * 
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 */

abstract contract Context {
    /// @dev Returns the address of the current message sender, which is available for internal functions.
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

/// @title ERC-20 Interface
/// @notice Interface for the compliance with the ERC-20 standard for fungible tokens.
interface IERC20 {
    /// @dev Returns the total token supply.
    function totalSupply() external view returns (uint256);

    /// @dev Returns the account balance of another account with address `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @dev Transfers `amount` tokens to address `recipient`, and MUST fire the `Transfer` event.
    function transfer(address recipient, uint256 amount) external returns (bool);

    /// @dev Returns the remaining number of tokens that the `spender` will be allowed to spend on behalf of `owner`.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @dev Sets `amount` as the allowance of `spender` over the caller's tokens, and MUST fire the `Approval` event.
    function approve(address spender, uint256 amount) external returns (bool);

    /// @dev Moves `amount` tokens from `sender` to `recipient` using the allowance mechanism and MUST fire the `Transfer` event.
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /// @notice Emitted when `value` tokens are moved from one account (`from`) to another (`to`).
    /// @dev MUST trigger when tokens are transferred, including zero value transfers.
    event Transfer(address indexed from, address indexed to, uint256 value);

    /// @notice Emitted when the allowance of a `spender` for an `owner` is set by a call to `approve`.
    /// @dev MUST trigger on any successful call to `approve`.
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @title Ownable
 * @dev A contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;
    address private _previousOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @title IUniswapV2Factory
 * @dev Interface for Uniswap V2 Factory.
 */
interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

/**
 * @title IUniswapV2Router02
 * @dev Interface for Uniswap V2 Router.
 */
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

/**
 * @title Intellexus Token Contract
 * @dev Implements the {IERC20} interface with additional features such as ownership and fee management.
 */
contract Intellexus is Context, IERC20, Ownable {
    string private constant _name = "Intellexus";
    string private constant _symbol = "IXC";
    uint8 private constant _decimals = 9;

    mapping(address => uint256) private _rOwned; // Reflective tokens owned by each account
    mapping(address => uint256) private _tOwned; // Total tokens owned by each account, including reflections
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) private _isExcludedFromFee; // Accounts excluded from fee
    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 100000000 * 10**9; // Total supply
    uint256 private _rTotal = (MAX - (MAX % _tTotal)); // Total reflective tokens
    uint256 private _tFeeTotal; // Total fees
    uint256 private _redisFeeOnBuy = 0; // Reflection fee on buy
    uint256 private _taxFeeOnBuy = 0; // Tax fee on buy
    uint256 private _redisFeeOnSell = 0; // Reflection fee on sell
    uint256 private _taxFeeOnSell = 0; // Tax fee on sell

    // Original Fee
    uint256 private _redisFee = _redisFeeOnSell; // Current reflection fee
    uint256 private _taxFee = _taxFeeOnSell; // Current tax fee

    uint256 private _previousredisFee = _redisFee; // Previous reflection fee for restoring after transactions
    uint256 private _previoustaxFee = _taxFee; // Previous tax fee for restoring after transactions

    mapping (address => bool) public preTrader; // Pre-trading whitelist
    address payable private _developmentAddress = payable(0x47F84d4307FEEBDeDC7426931EE1068c4142CD37); // Treasury MultiSig
    address payable private _marketingAddress = payable(0x47F84d4307FEEBDeDC7426931EE1068c4142CD37); // Treasury MultiSig

    IUniswapV2Router02 public uniswapV2Router; // Uniswap V2 Router
    address public uniswapV2Pair; // Uniswap V2 Pair for this token

    bool private tradingOpen; // Flag to control trading status
    bool private inSwap = false; // Lock to prevent re-entrance in swap function
    bool private swapEnabled = true; // Flag to enable/disable swapping mechanism

    uint256 public _maxTxAmount = 1000000 * 10**9; // Max transaction amount
    uint256 public _maxWalletSize = 2000000 * 10**9; // Max wallet holding amount
    uint256 public _swapTokensAtAmount = 400000 * 10**9; // Amount at which swap is triggered

    event MaxTxAmountUpdated(uint256 _maxTxAmount); // Event for updating max transaction amount

    /**
     * @dev Locks the swap during the execution of swap functions to prevent re-entrancy.
     */
    modifier lockTheSwap {
        inSwap = true;
        _;
        inSwap = false;
    }

    /**
     * @dev Sets the values for {_name}, {_symbol}, and {_decimals}.
     * Initializes the contract setting the deployer as the initial owner.
     */

    constructor() {
        _rOwned[_msgSender()] = _rTotal;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); //
        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_developmentAddress] = true;
        _isExcludedFromFee[_marketingAddress] = true;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public pure returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the name.
     */
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for display purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return tokenFromReflection(_rOwned[account]);
    }

    /**
     * @dev Transfers `amount` tokens from the caller's account to `recipient`.
     *
     * Emits a {Transfer} event.
     * Requirements:
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an {Approval} event.
     * Requirements:
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for `sender`'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()] - amount);
        return true;
    }

    /**
     * @dev Internal function to convert a reflected amount to its corresponding token amount.
     * @param rAmount Amount of tokens in reflections.
     * @return uint256 The resulting token amount.
     */
    function tokenFromReflection(uint256 rAmount) private view returns (uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate = _getRate();
        return rAmount / currentRate;
    }

    /**
     * @dev Internal function to remove all fee settings temporarily. Used for special transactions
     * where fees should not be applied.
     */
    function removeAllFee() private {
        if (_redisFee == 0 && _taxFee == 0) return;

        _previousredisFee = _redisFee;
        _previoustaxFee = _taxFee;

        _redisFee = 0;
        _taxFee = 0;
    }

    /**
     * @dev Restores the fee settings to their previous values. Used after special transactions
     * to reinstate the fee mechanism.
     */
    function restoreAllFee() private {
        _redisFee = _previousredisFee;
        _taxFee = _previoustaxFee;
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is an internal function that emits an {Approval} event.
     * Requirements:
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
    * @dev Internal function to handle token transfers, including business logic for trading restrictions,
    * fee application, and swapping tokens for ETH under specific conditions.
    * 
    * This function includes checks for trading status, max transaction amounts, wallet size restrictions,
    * and applies fees or swaps tokens based on the contract's state and the nature of the transfer.
    *
    * @param from The address sending the tokens.
    * @param to The address receiving the tokens.
    * @param amount The amount of tokens to be transferred.
    */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

    // Checks if the addresses are eligible for trading, enforcing restrictions before trading opens.
    if (from != owner() && to != owner() && !preTrader[from] && !preTrader[to]) {
        // Check if trading is open
        if (!tradingOpen) {
            require(preTrader[from], "TOKEN: This account cannot send tokens until trading is enabled");
        }

        require(amount <= _maxTxAmount, "TOKEN: Max Transaction Limit");

        // Ensure the recipient's balance does not exceed the maximum wallet size unless adding liquidity.
        if(to != uniswapV2Pair) {
            require(balanceOf(to) + amount <= _maxWalletSize, "TOKEN: Balance exceeds wallet size!");
        }

        // Logic to handle swapping tokens for ETH if certain conditions are met.
        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= _swapTokensAtAmount;

        if(contractTokenBalance >= _maxTxAmount) {
            contractTokenBalance = _maxTxAmount;
        }

        if (canSwap && !inSwap && from != uniswapV2Pair && swapEnabled && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
            swapTokensForEth(contractTokenBalance);
            uint256 contractETHBalance = address(this).balance;
            if (contractETHBalance > 0) {
                sendETHToFee(address(this).balance);
            }
        }
    }

    bool takeFee = true;

    // Determine if the transaction should take a fee.
    if ((_isExcludedFromFee[from] || _isExcludedFromFee[to]) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
        takeFee = false;
    } else {
        // Set Fee for Buys
        if(from == uniswapV2Pair && to != address(uniswapV2Router)) {
            _redisFee = _redisFeeOnBuy;
            _taxFee = _taxFeeOnBuy;
        }

        // Set Fee for Sells
        if (to == uniswapV2Pair && from != address(uniswapV2Router)) {
            _redisFee = _redisFeeOnSell;
            _taxFee = _taxFeeOnSell;
        }
    }

    _tokenTransfer(from, to, amount, takeFee);
}

    /**
    * @dev Swaps tokens for Ethereum (ETH) using the Uniswap protocol.
    * This function is marked with `lockTheSwap` to prevent reentrancy.
    * @param tokenAmount Amount of tokens to swap for ETH.
    */
    function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // Minimum amount of tokens to accept in swap
            path,
            address(this), // Recipient of the ETH
            block.timestamp // Deadline for the swap
        );
    }

    /**
    * @dev Sends ETH to the marketing address.
    * @param amount Amount of ETH to send.
    */
    function sendETHToFee(uint256 amount) private {
        _marketingAddress.transfer(amount);
    }

    /**
    * @dev Enables or disables trading. Only callable by the contract owner.
    * @param _tradingOpen The new trading state.
    */
    function setTrading(bool _tradingOpen) public onlyOwner {
        tradingOpen = _tradingOpen;
    }

    /**
    * @dev Allows manual swapping of contract tokens for ETH. Restricted to development or marketing addresses.
    */
    function manualswap() external {
        require(_msgSender() == _developmentAddress || _msgSender() == _marketingAddress, "Only authorized addresses can initiate swap");
        uint256 contractBalance = balanceOf(address(this));
        swapTokensForEth(contractBalance);
    }

    /**
    * @dev Allows manual sending of ETH to the marketing address. Restricted to development or marketing addresses.
    */
    function manualsend() external {
        require(_msgSender() == _developmentAddress || _msgSender() == _marketingAddress, "Only authorized addresses can send ETH");
        uint256 contractETHBalance = address(this).balance;
        sendETHToFee(contractETHBalance);
    }

    /**
    * @dev Handles token transfers, applying fee logic based on the transaction context.
    * @param sender The address sending the tokens.
    * @param recipient The address receiving the tokens.
    * @param amount The amount of tokens to transfer.
    * @param takeFee Specifies whether to apply transaction fees.
    */
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeFee
    ) private {
        if (!takeFee) removeAllFee();
        _transferStandard(sender, recipient, amount);
        if (!takeFee) restoreAllFee();
    }

    /**
    * @dev Performs the standard token transfer operation and applies fees.
    * @param sender The address sending the tokens.
    * @param recipient The address receiving the tokens.
    * @param tAmount The amount of tokens to transfer, including any fees.
    */
    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tTeam
        ) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender] - rAmount;
        _rOwned[recipient] = _rOwned[recipient] + rTransferAmount;
        _takeTeam(tTeam);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
    * @dev Allocates a portion of the transaction fees to the team's address.
    * @param tTeam The amount of tokens designated for the team.
    */
    function _takeTeam(uint256 tTeam) private {
        uint256 currentRate = _getRate();
        uint256 rTeam = tTeam * currentRate;
        _rOwned[address(this)] = _rOwned[address(this)] + rTeam;
    }


    /**
     * @dev Private function to reflect fees by decreasing `_rTotal` and increasing `_tFeeTotal`.
     * @param rFee Reflect fees in reflection tokens.
     * @param tFee Transaction fees in tokens to be added to total fees.
     */
    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal -= rFee;
        _tFeeTotal += tFee;
    }

    /**
     * @dev External payable function to receive ETH when sending directly to the contract's address.
     */
    receive() external payable {}

    /**
     * @dev Calculates and returns all necessary transaction values based on the transfer amount.
     * @param tAmount Amount of tokens to transfer.
     * @return rAmount Reflect amount.
     * @return rTransferAmount Reflect transfer amount.
     * @return rFee Reflect fee.
     * @return tTransferAmount Token transfer amount.
     * @return tFee Token fee.
     * @return tTeam Team tokens.
     */
    function _getValues(uint256 tAmount)
        private
        view
        returns (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee,
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tTeam
        )
    {
        (tTransferAmount, tFee, tTeam) = _getTValues(tAmount, _redisFee, _taxFee);
        uint256 currentRate = _getRate();
        (rAmount, rTransferAmount, rFee) = _getRValues(tAmount, tFee, tTeam, currentRate);
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tTeam);
    }

    /**
     * @dev Calculates token transfer amount, fee, and team allocation.
     * @param tAmount Transfer amount.
     * @param redisFee Reflection fee.
     * @param taxFee Tax fee.
     * @return tTransferAmount Total transfer amount after fees.
     * @return tFee Total reflection fee.
     * @return tTeam Total team allocation.
     */
    function _getTValues(
        uint256 tAmount,
        uint256 redisFee,
        uint256 taxFee
    )
        private
        pure
        returns (
            uint256 tTransferAmount,
            uint256 tFee,
            uint256 tTeam
        )
    {
        tFee = (tAmount * redisFee) / 100;
        tTeam = (tAmount * taxFee) / 100;
        tTransferAmount = tAmount - tFee - tTeam;
        return (tTransferAmount, tFee, tTeam);
    }

    /**
     * @dev Calculates reflect values based on token amounts and current rate.
     * @param tAmount Token amount.
     * @param tFee Token fee.
     * @param tTeam Team token allocation.
     * @param currentRate Current reflect rate.
     * @return rAmount Reflect amount.
     * @return rTransferAmount Reflect transfer amount.
     * @return rFee Reflect fee.
     */
    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 tTeam,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rFee
        )
    {
        rAmount = tAmount * currentRate;
        rFee = tFee * currentRate;
        uint256 rTeam = tTeam * currentRate;
        rTransferAmount = rAmount - rFee - rTeam;
        return (rAmount, rTransferAmount, rFee);
    }

    /**
     * @dev Returns the current rate of tokens to reflections.
     * @return The current rate of tokens to reflections.
     */
    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    /**
     * @dev Calculates the current supply of tokens and reflections, accounting for excluded accounts.
     * @return rSupply Current reflection supply.
     * @return tSupply Current token supply.
     */
    function _getCurrentSupply() private view returns (uint256 rSupply, uint256 tSupply) {
        rSupply = _rTotal;
        tSupply = _tTotal;
        // Here, additional logic could account for excluded accounts if necessary.
        return (rSupply, tSupply);
    }

    /**
     * @notice Sets the transaction fees for buys and sells.
     * @dev Only callable by the contract owner.
     * @param redisFeeOnBuy Reflection fee for buying transactions.
     * @param redisFeeOnSell Reflection fee for selling transactions.
     * @param taxFeeOnBuy Additional tax fee for buying transactions.
     * @param taxFeeOnSell Additional tax fee for selling transactions.
     */
    function setFee(uint256 redisFeeOnBuy, uint256 redisFeeOnSell, uint256 taxFeeOnBuy, uint256 taxFeeOnSell) public onlyOwner {
        _redisFeeOnBuy = redisFeeOnBuy;
        _redisFeeOnSell = redisFeeOnSell;
        _taxFeeOnBuy = taxFeeOnBuy;
        _taxFeeOnSell = taxFeeOnSell;
    }

    /**
     * @notice Sets the threshold amount of tokens required for swap and liquidity operations.
     * @dev Only callable by the contract owner.
     * @param swapTokensAtAmount The minimum token amount for swaps to occur.
     */
    function setMinSwapTokensThreshold(uint256 swapTokensAtAmount) public onlyOwner {
        _swapTokensAtAmount = swapTokensAtAmount;
    }

    /**
     * @notice Toggles the swap functionality on or off.
     * @dev Only callable by the contract owner.
     * @param _swapEnabled Boolean value to enable or disable swapping.
     */
    function toggleSwap(bool _swapEnabled) public onlyOwner {
        swapEnabled = _swapEnabled;
    }

    /**
     * @notice Sets the maximum transaction amount allowed in a transfer.
     * @dev Only callable by the contract owner.
     * @param maxTxAmount The maximum amount of tokens that can be transferred in a transaction.
     */
    function setMaxTxnAmount(uint256 maxTxAmount) public onlyOwner {
        _maxTxAmount = maxTxAmount;
    }

    /**
     * @notice Sets the maximum wallet size to prevent large holdings in a single wallet.
     * @dev Only callable by the contract owner.
     * @param maxWalletSize The maximum token amount a wallet can hold.
     */
    function setMaxWalletSize(uint256 maxWalletSize) public onlyOwner {
        _maxWalletSize = maxWalletSize;
    }

    /**
     * @notice Excludes or includes multiple accounts from transaction fees.
     * @dev Only callable by the contract owner.
     * @param accounts The addresses to be excluded or included.
     * @param excluded Whether the accounts should be excluded from fees.
     */
    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFee[accounts[i]] = excluded;
        }
    }

    /**
     * @notice Allows specified accounts to participate in trading before trading is opened to the public.
     * @dev Only callable by the contract owner.
     * @param accounts The addresses to be allowed for pre-trading.
     */
    function allowPreTrading(address[] calldata accounts) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            preTrader[accounts[i]] = true;
        }
    }

    /**
     * @notice Removes the ability of specified accounts to participate in pre-trading.
     * @dev Only callable by the contract owner.
     * @param accounts The addresses to have pre-trading permissions removed.
     */
    function removePreTrading(address[] calldata accounts) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            delete preTrader[accounts[i]];
        }
    }
}