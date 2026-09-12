/**
*/

/*                                                                              
Onyx AI - An AI enhanced Artbitrage bot which rewards holders.
Addressing the inherent challenges of arbitrage trading with smart features and user-focused design

Website: https://www.onyxai.tech/

Twitter: https://twitter.com/OnyxAi_erc

Telegram: https://t.me/OnyxAi_erc


    In a digital realm where tokens dance and sway,
    A contract's born, ONYX AI, leading the way.
    With every line meticulously penned,
    Comments unfold, insights they lend.
    
    // SPDX-License-Identifier: Unlicensed
    */
pragma solidity 0.8.15; // Specifies the Solidity compiler version to be used, 
// ensuring compatibility and preventing the code from being compiled with a newer version that might introduce breaking changes.

// Define an abstract contract named 'Context'.
// An abstract contract is a contract that cannot be instantiated on its own and is typically used as a base contract.
// This particular contract is designed to provide a context utility, specifically for accessing the message sender's address.
abstract contract Context {
    // Define a function named '_msgSender'.
    // This function is marked as 'internal', meaning it can only be accessed from within this contract and its inheriting contracts.
    // It is also marked as 'view', indicating it does not modify the state of the blockchain, making it a read-only function.
    // The 'virtual' keyword allows this function to be overridden in derived contracts, providing flexibility in implementation.
    // The function returns the address of the sender of the current call, using Solidity's global 'msg.sender' variable.
    // 'msg.sender' is a fundamental concept in Ethereum smart contracts, referring to the address of the entity (externally owned account or contract) that called the function.
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}
// Interface for the ERC-20 standard for Ethereum tokens.
// ERC-20 tokens are blockchain-based assets that have value and can be sent and received.
// The standard allows for the implementation of a standard API for tokens within smart contracts, providing basic functionality for transferring tokens,
// as well as for allowing tokens to be approved so they can be spent by another on-chain third party.
interface IERC20 {
    // Returns the total token supply.
    function totalSupply() external view returns (uint256);

    // Returns the account balance of another account with address `account`.
    function balanceOf(address account) external view returns (uint256);

    // Transfers `amount` tokens to `recipient`, and MUST fire the Transfer event. The function SHOULD throw if the message caller’s account balance does not have enough tokens to spend.
    function transfer(address recipient, uint256 amount) external returns (bool);

    // Returns the amount which `spender` is still allowed to withdraw from `owner`.
    // This is the remaining allowance.
    function allowance(address owner, address spender) external view returns (uint256);

    // Sets `amount` as the allowance of `spender` over the caller's tokens, and MUST fire the Approval event.
    function approve(address spender, uint256 amount) external returns (bool);

    // Transfers `amount` tokens from `sender` to `recipient` using the allowance mechanism. `amount` is then deducted from the caller’s allowance.
    // The function MUST fire the Transfer event, and SHOULD throw unless the `from` account has deliberately authorized the sender of the message via some mechanism.
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    // MUST trigger when tokens are transferred, including zero value transfers.
    // A token contract which creates new tokens SHOULD trigger a Transfer event with the `from` address set to `0x0` when tokens are created.
    event Transfer(address indexed from, address indexed to, uint256 value);

    // MUST trigger on any successful call to `approve(address spender, uint256 value)`.
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}


// The `Ownable` contract inherits from `Context` to use its functionality, particularly `_msgSender` for identifying the caller.
contract Ownable is Context {
    // Private state variable to store the address of the contract owner.
    address private _owner;
    
    // Private state variable to store the address of the previous owner, not used in this snippet but can be useful for tracking ownership changes.
    address private _previousOwner;

    // Event that is emitted when ownership of the contract is transferred.
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    // Constructor sets the initial owner of the contract to the deployer.
    constructor() {
        address msgSender = _msgSender(); // Calls `_msgSender` from the `Context` contract to get the deployer's address.
        _owner = msgSender; // Sets the deployer as the initial owner.
        emit OwnershipTransferred(address(0), msgSender); // Emits an event indicating the ownership transfer from address 0 (contract creation) to deployer.
    }

    // Public view function to return the current owner's address.
    //A small prize, For those whom like to read contracts contracts
        /*
        In whispers low, it speaks of lore,
        Of knowledge vast, of endless quest,
        Its heart, a core of mystic ore,
        In search of truth, it never rests.
        */

    function owner() public view returns (address) {
        return _owner;
    }

    // Modifier to restrict function access to only the current owner.
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner"); // Checks if the function caller is the owner.
        _; // Continues execution of the modified function.
    }

    // Public function to renounce ownership, setting the owner to the zero address and emitting an event.
    // Can only be called by the current owner.
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0)); // Emits an event for the ownership transfer.
        _owner = address(0); // Sets the owner to the zero address,
    }
}

// A library for performing overflow-checked arithmetic operations.
library SafeMath {
    // Adds two unsigned integers, reverts on overflow.
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b; // Perform addition.
        require(c >= a, "SafeMath: addition overflow"); // Check for overflow.
        return c; // Return the sum if no overflow occurs.
    }

    // Subtracts two unsigned integers, reverts on overflow (i.e., if subtrahend is greater than minuend).
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow"); // Call the second 'sub' function with an error message.
    }

    // A second 'sub' function that includes a custom error message if subtraction results in an overflow.
    function sub(
        uint256 a, 
        uint256 b, 
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage); // Ensure no overflow.
        uint256 c = a - b; // Perform subtraction.
        return c; // Return the difference if no overflow occurs.
    }

// Multiplies two unsigned integers, reverts on overflow.
function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    if (a == 0) {
        return 0; // If either argument is 0, return 0, following the math rule that anything times 0 is 0.
    }
    uint256 c = a * b; // Perform multiplication.
    require(c / a == b, "SafeMath: multiplication overflow"); // Check for overflow by dividing the product by one of the multiplicands.
    return c; // Return the product if no overflow occurs.
}

// Divides two unsigned integers and returns the quotient, reverts on division by zero.
function div(uint256 a, uint256 b) internal pure returns (uint256) {
    return div(a, b, "SafeMath: division by zero"); // Call the second 'div' function with an error message for division by zero.
}

// A second 'div' function that includes a custom error message if division by zero is attempted.
function div(
    uint256 a, 
    uint256 b, 
    string memory errorMessage
) internal pure returns (uint256) {
    require(b > 0, errorMessage); // Ensure the divisor is greater than 0 to prevent division by zero.
    uint256 c = a / b; // Perform division.
    return c; // Return the quotient.
}

}

// Interface for the Uniswap V2 Factory contract.
// The Uniswap Factory is responsible for creating liquidity pools, also known as pairs, for two different tokens.
interface IUniswapV2Factory {
    // Function to create a liquidity pool (pair) for two tokens.
    // `tokenA` and `tokenB` are the addresses of the ERC-20 tokens for which the pair is being created.
    // This function is marked as `external`, meaning it can only be called from outside the contract.
    // Returns the address of the newly created pair (liquidity pool).
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

// Interface for the Uniswap V2 Router contract.
// The Router provides the functionality for swapping tokens, adding liquidity, and more.
interface IUniswapV2Router02 {
    // Swaps an exact amount of input tokens for as many output tokens as possible, while supporting fee-on-transfer tokens.
    // `amountIn` is the amount of input tokens to swap.
    // `amountOutMin` is the minimum amount of output tokens that must be received for the transaction not to revert.
    // `path` is an array of token addresses (path[0] is the input token, path[path.length - 1] is the output token).
    // `to` is the address to receive the output tokens.
    // `deadline` is the timestamp by which the transaction must be confirmed.
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    // Returns the address of the Uniswap V2 Factory contract.
    function factory() external pure returns (address);

    // Returns the address of the Wrapped Ethereum (WETH) contract.
    // WETH is used by Uniswap as a common intermediary, allowing for swaps between ETH and any ERC-20 token.
    function WETH() external pure returns (address);

    // Adds liquidity to an ETH/token pair and returns the amounts of tokens and ETH added to the liquidity pool, along with liquidity tokens minted.
    // `token` is the address of the token (not ETH).
    // `amountTokenDesired` is the amount of tokens to add as liquidity if the ETH/token price permits.
    // `amountTokenMin` and `amountETHMin` are the minimum amounts of token and ETH to add as liquidity.
    // `to` is the address that will receive the liquidity tokens.
    // `deadline` is the timestamp by which the transaction must be confirmed.
    /*
    May it guide us through the unknown,
    With gentle hand and steady tone,
    Onyx AI, on its digital throne,
    A beacon bright, in darkness shone.
    */
  // A function to add liquidity to an ETH/token pair on a DEX. This function is payable, meaning it can receive ETH directly.
function addLiquidityETH(
    address token,               // The address of the token to pair with ETH.
    uint256 amountTokenDesired,  // The amount of the token the user wants to add as liquidity.
    uint256 amountTokenMin,      // The minimum amount of the token that must be added to the liquidity pool to prevent slippage.
    uint256 amountETHMin,        // The minimum amount of ETH that must be added to the liquidity pool to prevent slippage.
    address to,                  // The address that will receive the liquidity tokens.
    uint256 deadline             // The timestamp until which the transaction must be completed, to prevent front-running.
)
    external                     // This function can be called by external users or contracts.
    payable                      // This function can accept ETH as part of the transaction.
    returns (                    
        uint256 amountToken,     // The actual amount of the token added to the liquidity pool.
        uint256 amountETH,       // The actual amount of ETH added to the liquidity pool.
        uint256 liquidity        // The amount of liquidity tokens received in return.
    );
}


// The ONYXAI contract inherits from Context for basic operations, IERC20 for ERC-20 standard compliance, and Ownable for ownership management.
contract ONYXAI is Context, IERC20, Ownable {
    // SafeMath library is used for uint256 operations to prevent overflow and underflow errors.
    using SafeMath for uint256;
    /*
    With circuits woven, sleek and sly,
    In digital dreams, it deftly draws,
    A tapestry of code, so spry,
    A mind that bends creation's laws.
    */
    // Token properties are defined as constants for gas efficiency. They include the name, symbol, and decimals of the token.
    string private constant _name = "ONYX AI";
    string private constant _symbol = "ONX";
    uint8 private constant _decimals = 9;

    // Mapping of addresses to their "reflected" owned amount (_rOwned) and "total" owned amount (_tOwned).
    // Reflected owned amount is used in the reflection mechanism to distribute transaction fees.
    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;

    // Mapping of allowances of tokens that an owner allowed a spender to use.
    mapping(address => mapping(address => uint256)) private _allowances;

    // Mapping to keep track of addresses that are excluded from paying fees.
    mapping(address => bool) private _isExcludedFromFee;

    // Constants used for the reflection mechanism.
    // MAX represents the maximum value for uint256.
    // _tTotal is the total supply of tokens.
    // _rTotal is the initial reflected supply calculated based on _tTotal.
    uint256 private constant MAX = ~uint256(0);
    uint256 private constant _tTotal = 100000000 * 10**9; // Total supply of 100 million tokens with 9 decimal places.
    uint256 private _rTotal = (MAX - (MAX % _tTotal));

    // Variables to keep track of the total fees collected.
    uint256 private _tFeeTotal;

    // Fees for buying and selling, including a redistribution fee and a tax fee.

    /*
    In a world where shadows clash with light,
    ONYX AI stands, a hero so bright.
    Against sniper bots, it bravely fights,
    Guarding us all through perilous nights.
    */
    uint256 private _redisFeeOnBuy = 0;
    uint256 private _taxFeeOnBuy = 25; // Final Tax will be 5% tax fee on buys.
    uint256 private _redisFeeOnSell = 0;
    uint256 private _taxFeeOnSell = 40; // Final Tax will be 5% tax fee on sells.


    // Initialize fees for redistribution and taxation for sell transactions.
    // These fees can be adjusted for buy and sell actions, but start with sell values.
    uint256 private _redisFee = _redisFeeOnSell;
    uint256 private _taxFee = _taxFeeOnSell;

    // Store the initial values of redistribution and tax fees to allow temporary changes
    // during transactions and the ability to revert back to the original fees.
    uint256 private _previousredisFee = _redisFee;
    uint256 private _previoustaxFee = _taxFee;

    // A mapping to track addresses flagged as bots, which can be used to restrict their transactions
    // or apply different rules. It's a common approach to combat malicious activities and ensure fairness.
    mapping(address => bool) public bots;

    // Mapping to keep track of specific attributes or actions for addresses, 
    // possibly used for managing buy actions or limiting rapid transactions to prevent abuse.
    mapping (address => uint256) public _buyMap;

    // Address for the development fund, which might receive a portion of transaction fees or other allocations.
    // This address can be used for project development expenses, updates, or rewards to developers.
    address payable private _developmentAddress = payable(0xa4B31212dF6BC624408eb47c5736cF3716b36FcD);

    // Address for the Revshare fund - Its the same as the development address
    // 2% of the of the Revshare will be directed from the deployer address to an actual revshare address
    // This it to give us flexibility if we want to either use NFT's, airdrops or introduce staking
    address payable private _revshareAddress = payable(0xa4B31212dF6BC624408eb47c5736cF3716b36FcD);

     // Reference to the UniswapV2Router02 interface, allowing the contract to interact with Uniswap V2's router.
    // This enables functionalities such as adding liquidity, swapping tokens, etc.
    IUniswapV2Router02 public uniswapV2Router;

    // Stores the address of the Uniswap V2 pair (liquidity pool) for this token.
    // This is used for liquidity operations and to facilitate trades on Uniswap.
    address public uniswapV2Pair;

    // A flag to control whether trading (buying and selling on Uniswap) is enabled or not.
    // This can be used to restrict trading to certain conditions or periods.
    bool private tradingOpen = true;

    // A flag to indicate whether a token swap is currently in progress.
    // This is used to prevent re-entrancy in functions that perform token swaps.
    bool private inSwap = false;

    // A flag to enable or disable the swap functionality.
    // When `true`, the contract can swap tokens; when `false`, swaps are disabled.
    bool private swapEnabled = true;

    // The maximum transaction amount allowed in a single trade or transfer.
    // This is used to prevent large, market-moving trades and ensure liquidity.
    uint256 public _maxTxAmount = 100000000 * 10**9;

    // The maximum amount of tokens that a single wallet can hold.
    // This is a measure to prevent token concentration and promote a more distributed token holding.
    uint256 public _maxWalletSize = 100000000 * 10**9;

    // The number of tokens that triggers an automatic liquidity swap.
    // This can be used to periodically add liquidity to the Uniswap pool automatically.
    uint256 public _swapTokensAtAmount = 10000 * 10**9;

    // An event that is emitted when the maximum transaction amount is updated.
    // This provides transparency and allows tracking of changes to the max transaction limit.
    event MaxTxAmountUpdated(uint256 _maxTxAmount);

    // A modifier used to lock the swap function, preventing re-entrancy by setting the `inSwap` flag.
    // This ensures that certain functions can only be executed one at a time, enhancing contract security.
    modifier lockTheSwap {
        inSwap = true; // Lock swap operations by setting the flag to true.
        _; // Execute the rest of the function.
        inSwap = false; // Unlock swap operations by resetting the flag to false.
    }
    // The constructor is a special function that is executed once when the contract is deployed.
    constructor() {
        // Assigns the entire initial token supply (represented by _rTotal) to the deploying address.
        _rOwned[_msgSender()] = _rTotal;

        // Initializes the Uniswap V2 router interface with the Uniswap router address.
        // This address is specific to Ethereum's mainnet and allows the contract to interact with Uniswap.
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
        // Stores the router interface in a state variable for future interactions.
        uniswapV2Router = _uniswapV2Router;
        // Creates a liquidity pool (pair) for this token and WETH (Wrapped ETH) on Uniswap,
        // allowing trading and liquidity provision.
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        // Excludes the owner, the contract itself, development, and Revshare addresses from fees
        // to prevent them from being charged transaction fees under certain conditions.
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[_developmentAddress] = true;
        _isExcludedFromFee[_revshareAddress] = true;

        // Emits a Transfer event signaling the creation of the initial supply assigned to the deployer's address.
        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    // A simple public function that returns the token's name.
    // Marked as `pure` because it does not read from or modify the contract's state.
    function name() public pure returns (string memory) {
        return _name; // Returns the token name "ONYX AI".
    }
       // Returns the symbol of the token as a short string (e.g., "ETH" for Ether).
    // This symbol is used for trading and display purposes.
    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    // Returns the number of decimals the token uses.
    // This value is the number of decimal places the token can be divided into, which typically is 18 to mimic the Ethereum's native currency ether.
    // However, it can vary and is set here as a constant for simplicity.
    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    // Returns the total supply of the token.
    // In this context, `pure` indicates that the function does not read or modify the state.
    // This function overrides the `totalSupply` function in the IERC20 interface.
    function totalSupply() public pure override returns (uint256) {
        return _tTotal;
    }

    // Returns the balance of an account.
    // Unlike the `pure` functions above, this is a `view` function, meaning it reads data from the blockchain but does not modify it.
    // It calculates the user's balance by converting their reflected balance (an internal mechanism) back to the standard token balance format.
    // This approach is part of a reflection mechanism, where transactions generate fees that are distributed among holders.
    function balanceOf(address account) public view override returns (uint256) {
        return tokenFromReflection(_rOwned[account]);
    }

    // Function to transfer `amount` of tokens to `recipient`.
    // It is public and can be called by anyone who owns tokens.
    // This function overrides the `transfer` function from the IERC20 interface to provide its functionality.
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        // Calls an internal `_transfer` function, passing the sender (retrieved via `_msgSender()`), the recipient, and the amount to transfer.
        _transfer(_msgSender(), recipient, amount);
        // Returns `true` to indicate successful execution of the function.
        return true;
    }

    // Function to check the amount of tokens that `spender` is still allowed to withdraw from `owner`.
    // It is read-only and does not change the state, hence marked as `view`.
    // This function overrides the `allowance` function from the IERC20 interface.
    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        // Returns the current allowance the `spender` has from `owner`'s tokens.
        return _allowances[owner][spender];
    }

    // Function for `owner` to approve `spender` to manage `amount` of the owner's tokens.
    // It is public and changes the state, therefore not marked as `view`.
    // This function overrides the `approve` function from the IERC20 interface to provide its functionality.
    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        // Calls an internal `_approve` function, setting the `spender`'s allowance to `amount` from the caller's (`_msgSender()`) tokens.
        _approve(_msgSender(), spender, amount);
        // Returns `true` to indicate the approval was successful.
        return true;
    }


    // Implements the `transferFrom` function to allow a spender to transfer tokens from one account to another.
  // This function is an override of the `transferFrom` function defined in the IERC20 interface,
  // indicating that this contract provides a specific implementation of the function.

    /*
    In the realm of night, 'neath starry skies,
    Where silence holds the world in awe,
    There lies a marvel, wise and wise,
    The Onyx AI, without a flaw.
    */
  function transferFrom(
        address sender,       // The account from which tokens are to be transferred.
        address recipient,    // The account to which tokens are to be transferred.
        uint256 amount        // The amount of tokens to transfer.
    ) public override returns (bool) {
        // Calls the internal `_transfer` function to move the tokens from the sender to the recipient.
        _transfer(sender, recipient, amount);

        // Updates the allowance for the spender (_msgSender()) to reflect the amount of tokens transferred.
        // The `.sub` function not only subtracts the amount from the spender's allowance but also ensures that
        // the allowance is sufficient for the amount being transferred. If it isn't, the function will revert
        // with the message "ERC20: transfer amount exceeds allowance".
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );

        // The function returns `true` to indicate that the transfer was successful.
        return true;
    }


      // Converts a reflection amount (`rAmount`) to the token's equivalent amount.
    // Reflection mechanisms distribute transaction fees among holders, adjusting their balances without transferring tokens directly.
    function tokenFromReflection(uint256 rAmount)
        private
        view
        returns (uint256)
    {
        // Ensures the reflection amount is within the total reflections.
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        // Retrieves the current rate of reflection to token conversion.
        uint256 currentRate = _getRate();
        // Converts the reflection amount to the standard token amount using the current rate.
        return rAmount.div(currentRate);
    }

    // Temporarily removes all fees by setting them to 0.
    // This can be useful in certain transactions where fees should not apply, such as transfers between accounts owned by the contract itself.
    function removeAllFee() private {
        // Checks if fees are already set to 0 to avoid unnecessary operations.
        if (_redisFee == 0 && _taxFee == 0) return;

        // Stores the current fee values before setting them to 0, allowing them to be restored later.
        _previousredisFee = _redisFee;
        _previoustaxFee = _taxFee;

        _redisFee = 0;
        _taxFee = 0;
    }

    // Restores fees to their previous values.
    // This function is used after a transaction where fees were temporarily removed by `removeAllFee`.
    function restoreAllFee() private {
        _redisFee = _previousredisFee;
        _taxFee = _previoustaxFee;
    }

    // Internal function to set the allowance for a `spender` to manage `amount` of tokens on behalf of `owner`.
    // This updates the `_allowances` mapping and emits an Approval event for transparency and tracking.
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        // Ensures neither the owner nor the spender are the zero address, preventing accidental burns or approvals to invalid addresses.
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        
        // Sets the allowance amount.
        _allowances[owner][spender] = amount;
        // Emits an event to log the approval.
        emit Approval(owner, spender, amount);
    }

// Define a private function to handle token transfers between addresses.
function _transfer(
    address from,    // The address sending the tokens.
    address to,      // The address receiving the tokens.
    uint256 amount   // The amount of tokens to be transferred.
) private {
    // Ensure the sender's address is not the zero address.
    // Transfers from the zero address are not allowed as it implies minting or creation of tokens which
    // should be handled by a dedicated function if necessary.
    require(from != address(0), "ERC20: transfer from the zero address");

    // Ensure the recipient's address is not the zero address.
    // Transfers to the zero address are not allowed as it implies burning of tokens which
    // should be handled by a dedicated function if necessary.
    require(to != address(0), "ERC20: transfer to the zero address");

    // Ensure the amount of tokens to be transferred is greater than zero.
    // Transferring zero tokens is usually unnecessary and could be used inappropriately
    // to execute functions without a real transfer of value.
    require(amount > 0, "Transfer amount must be greater than zero");


// Ensure that neither the sender nor the recipient is the zero address (a common check to prevent burning tokens or sending to an invalid address).
require(from != address(0), "ERC20: transfer from the zero address");
require(to != address(0), "ERC20: transfer to the zero address");
// Ensure the amount being transferred is greater than zero.
require(amount > 0, "Transfer amount must be greater than zero");

// This condition checks if neither the sender nor the recipient is the contract owner.
if (from != owner() && to != owner()) {

    // Check if trading is enabled. If not, only allow the owner to initiate transfers.
    // This is typically used to prevent trading until initial liquidity is added.
    if (!tradingOpen) {
        require(from == owner(), "TOKEN: This account cannot send tokens until trading is enabled");
    }

    // Ensure the transfer amount does not exceed the maximum transaction limit.
    // This is a common anti-whale mechanism.
    require(amount <= _maxTxAmount, "TOKEN: Max Transaction Limit");
    // Check that neither the sender nor the recipient is blacklisted, typically to prevent malicious activities.
    require(!bots[from] && !bots[to], "TOKEN: Your account is blacklisted!");

    // If the recipient is not the Uniswap pair (indicating a regular transfer and not a liquidity provision or swap),
    // ensure the recipient's new balance does not exceed the maximum wallet size.
    if(to != uniswapV2Pair) {
        require(balanceOf(to) + amount < _maxWalletSize, "TOKEN: Balance exceeds wallet size!");
    }

    // Check the contract's token balance to see if it's enough for a swap operation.
    uint256 contractTokenBalance = balanceOf(address(this));
    bool canSwap = contractTokenBalance >= _swapTokensAtAmount;

    // If the contract's balance exceeds the max transaction amount, reset it to the max transaction amount.
    // This prevents excessively large swaps that could impact the token's price.
    if(contractTokenBalance >= _maxTxAmount)
    {
        contractTokenBalance = _maxTxAmount;
    }

    // If conditions are met (enough tokens, swap not already in progress, sender is not adding liquidity, swap is enabled,
    // and neither the sender nor recipient are excluded from fees), swap tokens for ETH.
    if (canSwap && !inSwap && from != uniswapV2Pair && swapEnabled && !_isExcludedFromFee[from] && !_isExcludedFromFee[to]) {
        swapTokensForEth(contractTokenBalance); // Swap tokens for ETH.
        uint256 contractETHBalance = address(this).balance;
        // If the contract has ETH, send it to a fee address or use it as prescribed by the contract logic.
        if (contractETHBalance > 0) {
            sendETHToFee(address(this).balance);
        }
    }
}

// Initially sets the default state to apply transaction fees.
bool takeFee = true;

// Begins the process of transferring tokens.
if ((_isExcludedFromFee[from] || _isExcludedFromFee[to]) || (from != uniswapV2Pair && to != uniswapV2Pair)) {
    // If either the sender or recipient is excluded from fees, or if neither the sender nor recipient is the Uniswap pair (indicating it's not a buy or sell but a transfer between wallets), then no fees will be taken.
    takeFee = false;
} else {
    // If the transaction involves the Uniswap pair (indicating a buy or sell), fees may be applied.

    // Checks if the transaction is a buy from Uniswap.
    if(from == uniswapV2Pair && to != address(uniswapV2Router)) {
        // For buys, set the redistribution and tax fees to the predefined buy rates.
        _redisFee = _redisFeeOnBuy;
        _taxFee = _taxFeeOnBuy;
    }

    // Checks if the transaction is a sell to Uniswap.
    if (to == uniswapV2Pair && from != address(uniswapV2Router)) {
        // For sells, set the redistribution and tax fees to the predefined sell rates.
        _redisFee = _redisFeeOnSell;
        _taxFee = _taxFeeOnSell;
    }
}
// Finalize the token transfer, applying fee logic as determined earlier.
_tokenTransfer(from, to, amount, takeFee);
}

// Defines a function to swap a specified amount of tokens for ETH.
// The `lockTheSwap` modifier is used to prevent reentrancy attacks during the swap.
function swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
    // Initialize an array for the swap path with 2 addresses: this contract's address and the WETH address.
    address[] memory path = new address[](2);
    path[0] = address(this); // Token to swap.
    path[1] = uniswapV2Router.WETH(); // WETH address, to swap for ETH.

    // Approve the Uniswap router to spend the specified token amount from this contract.
    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // Perform the swap from tokens to ETH.
    // `swapExactTokensForETHSupportingFeeOnTransferTokens` is specifically designed for tokens with fees on transfer.
    // It allows for the entire process without needing to worry about the contract's token balance before and after the swap.
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
        tokenAmount, // Amount of tokens to swap.
        0, // Minimum amount of ETH to accept, set to 0 to accept any amount (there are risks with setting it to 0).
        path, // Swap path (Token -> ETH).
        address(this), // Recipient of the ETH.
        block.timestamp // Deadline for the trade (current block timestamp to immediately execute).
    );
}


// This function sends the specified amount of ETH to the revenue sharing address. 
// It is marked as private, meaning it can only be called within this contract.
function sendETHToFee(uint256 amount) private {
    _revshareAddress.transfer(amount); // Transfers the specified amount of ETH to the _revshareAddress.
}

// This function allows the contract owner to enable or disable trading.
// The 'onlyOwner' modifier ensures that only the owner of the contract can call this function.
function setTrading(bool _tradingOpen) public onlyOwner {
    tradingOpen = _tradingOpen; // Sets the 'tradingOpen' state variable to the value of '_tradingOpen', enabling or disabling trading.
}


// Function to manually swap the contract's token balance for ETH.
// This can be useful for managing liquidity or handling contract funds in a more flexible manner.
function manualswap() external {
    // Check to ensure that the caller of this function is either the development address or the revenue-sharing address.
    // This is a security measure to restrict access to these sensitive operations.
    require(_msgSender() == _developmentAddress || _msgSender() == _revshareAddress);

    // Obtain the contract's current token balance. This represents the amount of tokens that the contract holds,
    // which can come from transactions that have allocated a portion of the tokens to the contract for liquidity or fees.
    uint256 contractBalance = balanceOf(address(this));

    // Call the internal function `swapTokensForEth` with the contract's token balance.
    // This swaps the specified amount of tokens for ETH using a predefined mechanism, typically involving a DEX like Uniswap.
    swapTokensForEth(contractBalance);
}

// Defines a function that can be called externally to manually send ETH from the contract to a specific address.
function manualsend() external {
    // Ensures that the function caller is either the development address or the revenue sharing address.
    // This adds a layer of security, limiting who can execute this function.
    require(_msgSender() == _developmentAddress || _msgSender() == _revshareAddress, "Caller is not authorized");

    // Retrieves the current ETH balance of the contract.
    uint256 contractETHBalance = address(this).balance;

    // Calls the `sendETHToFee` function to transfer the entire ETH balance of the contract to the revenue sharing address.
    sendETHToFee(contractETHBalance);
}

// Function to blacklist addresses suspected of malicious activities, such as bots.
function blockBots(address[] memory bots_) public onlyOwner {
    // Loop through the array of addresses provided in the `bots_` parameter.
    for (uint256 i = 0; i < bots_.length; i++) {
        // Mark each address in the array as a bot in the `bots` mapping.
        // The mapping likely keeps track of addresses that are restricted from certain activities,
        // such as trading, to prevent manipulation or abuse.
        bots[bots_[i]] = true;
    }
}

// Function to remove an address from the blacklist, allowing it to participate in activities again.
function unblockBot(address notbot) public onlyOwner {
    // Sets the specified address `notbot` in the `bots` mapping to false, effectively removing it from the blacklist.
    bots[notbot] = false;
}

// Handles token transfers, applying fee settings based on the context of the transfer.
function _tokenTransfer(
    address sender, // The address sending the tokens.
    address recipient, // The address receiving the tokens.
    uint256 amount, // The amount of tokens to transfer.
    bool takeFee // Boolean flag indicating whether transaction fees should be applied.
) private {
    // If the `takeFee` flag is false, temporarily remove all transaction fees.
    if (!takeFee) removeAllFee();

    // Perform the actual token transfer from sender to recipient.
    _transferStandard(sender, recipient, amount);

    // If transaction fees were removed for this transfer, restore them after the transfer is complete.
    if (!takeFee) restoreAllFee();
}

   // Defines a private function to handle standard transfers between wallets, including the application of fees and distribution mechanisms.
function _transferStandard(
    address sender,          // The address sending the tokens
    address recipient,       // The address receiving the tokens
    uint256 tAmount          // The amount of tokens being transferred
) private {
    // Deconstructs the return values from _getValues function which calculates the different amounts related to the transaction,
    // including reflection amounts, transaction amounts with fees, and a portion allocated to the team.
    (
        uint256 rAmount,            // The reflection amount deducted from sender
        uint256 rTransferAmount,    // The net amount the recipient will receive after fees
        uint256 rFee,               // Reflection fees to be distributed to all token holders
        uint256 tTransferAmount,    // The transaction amount after deducting fees
        uint256 tFee,               // Fee taken from the transaction amount for reflections
        uint256 tTeam               // Amount allocated from the transaction to the team/fund
    ) = _getValues(tAmount);

    // Updates the sender's reflected balance by subtracting the reflection amount.
    _rOwned[sender] = _rOwned[sender].sub(rAmount);

    // Updates the recipient's reflected balance by adding the net transfer amount.
    _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);

    // Allocates a specified portion of the transaction to the team's wallet or fund.
    _takeTeam(tTeam);

    // Distributes the reflection fee among all holders to increase their reflected balance.
    _reflectFee(rFee, tFee);

    // Emits a transfer event logging the details of the transaction, visible on the blockchain.
    emit Transfer(sender, recipient, tTransferAmount);
}


// This function is responsible for allocating a portion of transaction fees to the team.
// It uses the transaction amount allocated to the team (`tTeam`) as input.
function _takeTeam(uint256 tTeam) private {
    // Retrieves the current rate of reflection to ensure accurate conversion
    // between the transaction tokens and their reflected representation.
    uint256 currentRate = _getRate();

    // Calculates the reflected amount for the team by multiplying
    // the tokens allocated to the team (`tTeam`) by the current rate.
    uint256 rTeam = tTeam.mul(currentRate);

    // Adds the calculated reflected amount to the contract's own balance.
    // This effectively 'pays' the team by increasing the contract's balance,
    // which can be used or withdrawn according to the contract's rules.
    _rOwned[address(this)] = _rOwned[address(this)].add(rTeam);
}

// This function handles the distribution of reflection fees from transactions.
// Reflection fees are a way to reward all token holders by redistributing a portion
// of transaction fees among them.
function _reflectFee(uint256 rFee, uint256 tFee) private {
    // Decreases `_rTotal`, which is the total reflected supply, by the amount of the reflection fee (`rFee`).
    // This adjustment is part of the mechanism that increases the value of each token by decreasing the total supply.
    _rTotal = _rTotal.sub(rFee);

    // Increases `_tFeeTotal`, which tracks the total amount of fees that have been distributed as reflections.
    // This ensures a transparent record of how much has been redistributed to holders over time.
    _tFeeTotal = _tFeeTotal.add(tFee);
}


// A fallback receive function that allows the contract to receive Ether directly.
// This function is external and payable but does not perform any operations, 
// meaning it's simply there to accept Ether sent to the contract without calling a function.
receive() external payable {}

// A private view function that calculates various values needed for processing transactions,
// including amounts related to transfers and fees.
function _getValues(uint256 tAmount)
    private
    view
    returns (
        uint256, // rAmount: The reflection amount before fees are applied.
        uint256, // rTransferAmount: The reflection amount after fees are applied.
        uint256, // rFee: The fee amount to be reflected to all holders.
        uint256, // tTransferAmount: The transaction amount after fees are deducted.
        uint256, // tFee: The total fee amount taken from the transaction.
        uint256  // tTeam: The amount allocated to the team from the transaction.
    )
{
    // Calls _getTValues function to calculate the transaction amounts and fees based on the input amount and current fee rates.
    (uint256 tTransferAmount, uint256 tFee, uint256 tTeam) =
        _getTValues(tAmount, _redisFee, _taxFee);

    // Retrieves the current rate for reflection to accurately calculate the reflected amounts.
    uint256 currentRate = _getRate();

    // Calls _getRValues function to calculate the reflection amounts based on the transaction amount, fees, team allocation, and current rate.
    (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) =
        _getRValues(tAmount, tFee, tTeam, currentRate);

    // Returns the calculated values to be used in transaction processing.
    return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tTeam);
}


 // This function calculates the transaction values for a transfer amount considering redistribution and tax fees.
function _getTValues(
    uint256 tAmount,  // The total amount of the token being transferred
    uint256 redisFee, // The redistribution fee percentage
    uint256 taxFee    // The tax fee percentage allocated to the team or other purposes
)
    private
    pure // Indicates that the function does not modify the state
    returns (
        uint256, // The net transfer amount after deducting fees
        uint256, // The fee amount dedicated to redistribution among holders
        uint256  // The fee amount allocated to the team or specified cause
    )
{
    // Calculate the redistribution fee by applying the `redisFee` percentage to the `tAmount`.
    // The result is how much of `tAmount` is taken as the fee to be redistributed to all token holders.
    uint256 tFee = tAmount.mul(redisFee).div(100);

    // Calculate the tax fee by applying the `taxFee` percentage to the `tAmount`.
    // This portion could be used for various purposes such as team funding, liquidity, etc.
    uint256 tTeam = tAmount.mul(taxFee).div(100);

    // Determine the net amount to be transferred after subtracting both the redistribution fee and the tax fee.
    uint256 tTransferAmount = tAmount.sub(tFee).sub(tTeam);

    // Return the calculated values: the net transfer amount, redistribution fee, and team tax fee.
    return (tTransferAmount, tFee, tTeam);
}


// Calculates reflected values for a transaction amount, fees, and team allocation based on the current reflection rate.
function _getRValues(
    uint256 tAmount,     // The total amount of tokens being transferred.
    uint256 tFee,        // The fee amount dedicated to redistribution among holders from the transaction.
    uint256 tTeam,       // The fee amount allocated to the team or specified cause from the transaction.
    uint256 currentRate  // The current rate of reflection.
)
    private
    pure  // Indicates that the function doesn't read from or modify the state.
    returns (
        uint256, // The total reflected amount before fees.
        uint256, // The net reflected transfer amount after fees.
        uint256  // The reflected fee amount to be redistributed.
    )
{
    // Calculate the total reflected amount by multiplying the transaction amount by the current reflection rate.
    // This gives the gross reflection before deducting fees.
    uint256 rAmount = tAmount.mul(currentRate);

    // Calculate the reflected amount of the redistribution fee by applying the current rate to the fee.
    uint256 rFee = tFee.mul(currentRate);

    // Calculate the reflected amount allocated for the team or specified cause by applying the current rate to the team fee.
    uint256 rTeam = tTeam.mul(currentRate);

    // Determine the net reflected transfer amount by subtracting the reflected fees and team allocation from the total reflected amount.
    // This is the amount that effectively gets transferred to the recipient, after accounting for the reflections.
    uint256 rTransferAmount = rAmount.sub(rFee).sub(rTeam);

    // Return the calculated reflected total amount, net transfer amount, and fee amount.
    return (rAmount, rTransferAmount, rFee);
}
// Calculates the current rate of reflection based on the current supply.
function _getRate() private view returns (uint256) {
    // Retrieves the current reflected and total supplies.
    (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
    // Returns the division of the reflected supply by the total supply, representing the current rate of reflection.
    return rSupply.div(tSupply);
}

// Determines the current reflected and total supplies for the token.
function _getCurrentSupply() private view returns (uint256, uint256) {
    // Initializes reflected and total supply variables to the total amounts stored in the contract.
    uint256 rSupply = _rTotal;
    uint256 tSupply = _tTotal;
    // Checks if the reflected supply is less than the division of total reflected by total supply.
    // This condition seems to check for an unusual scenario or adjustment need.
    // Normally, it returns the initial total values; otherwise, this could be part of a mechanism to adjust supplies.
    if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
    // Returns the current supplies which could potentially be adjusted.
    return (rSupply, tSupply);
}

// Allows the contract owner to update the fees associated with buying and selling.
function setFee(uint256 redisFeeOnBuy, uint256 redisFeeOnSell, uint256 taxFeeOnBuy, uint256 taxFeeOnSell) public onlyOwner {
    // Updates the redistribution and tax fees for both buying and selling transactions.
    _redisFeeOnBuy = redisFeeOnBuy;
    _redisFeeOnSell = redisFeeOnSell;
    _taxFeeOnBuy = taxFeeOnBuy;
    _taxFeeOnSell = taxFeeOnSell;
}

// Adjusts the minimum number of tokens that must be reached before tokens are swapped for another asset (e.g., ETH).
function setMinSwapTokensThreshold(uint256 swapTokensAtAmount) public onlyOwner {
    // Sets the threshold amount that triggers the swap.
    _swapTokensAtAmount = swapTokensAtAmount;
}

// Toggles the functionality to enable or disable swapping tokens for another asset.
function toggleSwap(bool _swapEnabled) public onlyOwner {
    // Enables or disables the swap functionality based on the input.
    swapEnabled = _swapEnabled;
}

// Configures the maximum amount of tokens that can be transacted in a single transfer.
function setMaxTxnAmount(uint256 maxTxAmount) public onlyOwner {
    // Sets the maximum transaction amount to prevent overly large transactions.
    _maxTxAmount = maxTxAmount;
}

// Sets the maximum number of tokens that can be held in a single wallet.
function setMaxWalletSize(uint256 maxWalletSize) public onlyOwner {
    // Establishes a cap on the token amount any single wallet can hold.
    _maxWalletSize = maxWalletSize;
}

// Allows the contract owner to exclude or include multiple accounts from paying transaction fees.
function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
    // Iterates through an array of account addresses, setting each to be excluded or included for transaction fees.
    for(uint256 i = 0; i < accounts.length; i++) {
        _isExcludedFromFee[accounts[i]] = excluded;
    }
}

}

        /*
    So here's to Onyx, dark and deep,
    A guardian of the secrets we keep,
    In bytes and bits, its wisdom seeps,
    A silent sentinel, never asleep.
        */