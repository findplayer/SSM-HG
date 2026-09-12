/*
Website: https://www.texitmoney.com/
Telegram: https://t.me/texitcoin
Twitter: https://twitter.com/texitcoincrypto?s=11
*/
// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
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
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 *
 * The default value of {decimals} is 18. To change this, you should override
 * this function so it returns a different value.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(
        address account
    ) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
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

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
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

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
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
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
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

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
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

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

/// Uniswap factory interface
interface IFactory {
    function createPair(
        address tokenA,
        address tokenB
    ) external returns (address pair);
}

/// Uniswap Router interface
interface IUniswapRouter {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function getAmountsOut(
        uint256 amountIn,
        address[] calldata path
    ) external view returns (uint256[] memory amounts);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
}

/// @title Token: ERC20 token with buy and sell fees
contract Texit is ERC20, Ownable {
    /// @notice MAX SUPPLY 1 Billion Token
    uint256 private constant MAX_SUPPLY = 1_000_000_000 * 1e18;
    /// @notice max buy per tx
    uint256 maxBuyAmountPerTx = MAX_SUPPLY / 100; // 1% Of the supply
    /// @notice max sell per tx
    uint256 maxSellAmountPerTx = MAX_SUPPLY / 100; // 1% Of the supply
    /// @notice max Wallet amount
    uint256 maxWalletAmount = (MAX_SUPPLY * 2) / 100;// 2% Of the supply
    /// @notice operational wallet address
    address public operationalWallet = 0x55F772761d7277629f71afD50B7a803c67F3c151;
    /// @notice uniswapV2Router
    IUniswapRouter public immutable uniswapV2Router;
    /// @notice uniswapPair
    address public immutable uniswapPair;
    /// fees struct
    struct BuyFee {
        uint256 operational;
        uint256 autoLP;
    }
    struct SellFee {
        uint256 operational;
        uint256 autoLP;
    }

    /// @notice buyFee
    BuyFee public buyFee;
    /// @notice sellFee
    SellFee public sellFee;
    /// @notice swapping status
    bool swapping = false;
    /// @notice manage exclude / incclude from fees
    mapping(address => bool) isExcludedFromFees;

    ///  errors
    error OnlyoperationalWallet();
    error MaxBuyPerTxExceeds();
    error MaxSellPerTxExceeds();
    error MaxWalletLimitExceeds();
    error OnlyTaxAdmin();
    error Renounced();
    error MinOnePercent();
    error ZeroAddress();

    constructor() ERC20("Texit Coin", "TEXIT") {
        uniswapV2Router = IUniswapRouter(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D //UNISWAP V2 ROUTER 
        );
        uniswapPair = IFactory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        
        buyFee.operational = 3;
        buyFee.autoLP = 1;

        sellFee.operational = 3;
        sellFee.autoLP = 1;

        isExcludedFromFees[owner()] = true;
        isExcludedFromFees[address(this)] = true;
        isExcludedFromFees[operationalWallet] = true;
        _mint(msg.sender, MAX_SUPPLY);
    }

    receive() external payable {}

    /// @dev claim any erc20 token, accidently sent to token contract
    /// @param token: token to rescue
    /// @param amount: amount to rescue
    /// Requirements -
    /// only operational wallet can rescue stucked tokens
    function claimStuckedERC20(address token, uint256 amount) external {
        if (msg.sender != operationalWallet) {
            revert OnlyoperationalWallet();
        }
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, operationalWallet, amount)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "BARC: TOKEN_CLAIM_FAILED"
        );
    }

    /// @dev exclude or include a address from / to fees
    /// @param user: user address to exclude or include
    /// @param excluded: true to exclude, false to include
    function exlcudeFromFees(address user, bool excluded) external onlyOwner {
        isExcludedFromFees[user] = excluded;
    }

    /// @dev update max buy  amount per tx globally
    /// @param _percent: pecent of total supply
    /// Requirements -
    /// must be 1 or more
    function updateBuyAmountPerTx(uint256 _percent) external onlyOwner {
        if (_percent < 1) {
            revert MinOnePercent();
        }
        maxBuyAmountPerTx = (totalSupply() * _percent) / 100;
    }

    /// @dev update max sell amount per tx globally
    /// @param _percent: pecent of total supply
    /// Requirements -
    /// must be 1 or more
    function updateSellAmountPerTx(uint256 _percent) external onlyOwner {
        if (_percent < 1) {
            revert MinOnePercent();
        }
        maxSellAmountPerTx = (totalSupply() * _percent) / 100;
    }

    /// @dev update max wallet amount (antiwhale) globally
    /// @param _percent: pecent of total supply
    /// Requirements -
    /// must be 1 or more
    function updateMaxWalletPercent(uint256 _percent) external onlyOwner {
        if (_percent < 1) {
            revert MinOnePercent();
        }
        maxWalletAmount = (totalSupply() * _percent) / 100;
    }

    /// @dev update operational wallet
    /// @param _newOperationalWallet: new wallet for fees
    function setOperationalWallet (address _newOperationalWallet) external onlyOwner {
        if(_newOperationalWallet == address(0)){revert ZeroAddress();}
        operationalWallet = _newOperationalWallet;
    }

    /// @dev update buy tax globally
    /// @param _operational: new  operational tax on buy
    /// @param _lp: new lp tax on buy
    function updateBuyTax(
        uint256 _operational,
        uint256 _lp
    ) external onlyOwner{
        buyFee.operational = _operational;
        buyFee.autoLP = _lp;
    }

    /// @dev update sell tax globally
    /// @param _operational: new  operational tax on sell
    /// @param _lp: new lp tax on sell
    function updateSellTax(
        uint256 _operational,
        uint256 _lp
    ) external {
        sellFee.operational = _operational;
        sellFee.autoLP = _lp;
    }

    /// @notice manage token transfer and fees
    ///         fees is applicable for first 48 hours from launch
    ///         after 48 hours, fees will become zero globally
    /// @dev See {ERC20-_transfer}
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        bool takeFee = true;
        if (isExcludedFromFees[from] || isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (takeFee) {
            uint256 fee;
            if(to != uniswapPair){
                if(amount + balanceOf(to) > maxWalletAmount){revert MaxWalletLimitExceeds();}
            }
            if (from == uniswapPair) {
                if (amount > maxBuyAmountPerTx) {
                    revert MaxBuyPerTxExceeds();
                }
                uint256 totalBuyFee = buyFee.operational +
                    buyFee.autoLP;
                if (totalBuyFee > 0) {
                    fee = (amount * totalBuyFee) / 100;
                }
            } else if (to == uniswapPair) {
                if (amount > maxSellAmountPerTx) {
                    revert MaxSellPerTxExceeds();
                }
                uint256 totalSellFee = sellFee.operational +
                    sellFee.autoLP;
                if (totalSellFee > 0) {
                    fee = (amount * totalSellFee) / 100;
                }
            }

            amount = amount - fee;
            if (fee > 0) {
                super._transfer(from, address(this), fee);
            }
            
        }
        uint256 contractBalance = balanceOf(address(this));

        bool canSwap = contractBalance >= 100e18 &&
            from != uniswapPair &&
            (!isExcludedFromFees[from]) &&
            !swapping;
        if (canSwap) {
            swapping = true;
            swapAndLiquify(contractBalance);
            swapping = false;
        }

        super._transfer(from, to, amount);
    }

    /// @notice swap and liquify
    /// transfer collected tax to designated addresses as per there share
    function swapAndLiquify(uint256 tokens) private {
        uint256 total = buyFee.autoLP +
            sellFee.autoLP +
            buyFee.operational +
            sellFee.operational;
        uint256 lpHalf = ((buyFee.autoLP + sellFee.autoLP) * tokens) /
            (total * 2);
        uint256 tokensForSwap = (tokens - lpHalf);
        swapTokensForETH(tokensForSwap);
        uint256 ethBalance = address(this).balance;
        uint256 lpEth = (ethBalance * lpHalf) / tokens;
        /// add liquidity
        if (lpEth > 0 && lpHalf > 0) {
            addLiquidity(lpEth, lpHalf);
        }
        /// sent eth to operational wallet
        if (address(this).balance > 0) {
            bool sent;
            (sent, ) = operationalWallet.call{value: address(this).balance}("");
        }
    }

    ///@notice swap the tax tokens for eth and send to operational wallet
    function swapTokensForETH(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> wbnb
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        if (allowance(address(this), address(uniswapV2Router)) < tokenAmount) {
            _approve(
                address(this),
                address(uniswapV2Router),
                type(uint256).max
            );
        }

        uint256 out = uniswapV2Router.getAmountsOut(tokenAmount, path)[1];
        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            (out * 20) / 100, //20% Slippage
            path,
            address(this),
            block.timestamp + 360
        );
    }

    /// add liquidity
    function addLiquidity(uint256 ethAmount, uint256 tokens) private {
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokens,
            0,
            0,
            address(0xdead), // burn lp
            block.timestamp + 360
        );
    }
}