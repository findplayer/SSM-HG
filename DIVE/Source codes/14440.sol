/**
 * ██████  ███████ ██    ██  ██████  ██      ██    ██ ███████ ██  ██████  ███    ██
 * ██   ██ ██      ██    ██ ██    ██ ██      ██    ██     ██  ██ ██    ██ ████   ██
 * ██████  █████   ██    ██ ██    ██ ██      ██    ██   ██    ██ ██    ██ ██ ██  ██
 * ██   ██ ██       ██  ██  ██    ██ ██      ██    ██  ██     ██ ██    ██ ██  ██ ██
 * ██   ██ ███████   ████    ██████  ███████  ██████  ███████ ██  ██████  ██   ████
 * 
 * @title BRO Revenue Share
 * 
 * @notice This is a smart contract developed by Revoluzion for BRO Revenue Share.
 * 
 * @dev This smart contract was developed based on the general
 * OpenZeppelin Contracts guidelines where functions revert instead of
 * returning `false` on failure. 
 * 
 * @author Revoluzion Ecosystem
 * @custom:email support@revoluzion.io
 * @custom:telegram https://t.me/RevoluzionEcosystem
 * @custom:website https://revoluzion.io
 * @custom:dapp https://revoluzion.app
 */
 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/********************************************************************************************
  LIBRARY
********************************************************************************************/

/**
 * @title Address Library
 *
 * @notice Collection of functions providing utility for interacting with addresses.
 */
library Address {

    // ERROR

    /**
     * @notice Error indicating insufficient balance while performing an operation.
     *
     * @param account Address where the balance is insufficient.
     */
    error AddressInsufficientBalance(address account);

    /**
     * @notice Error indicating an attempt to interact with a contract having empty code.
     *
     * @param target Address of the contract with empty code.
     */
    error AddressEmptyCode(address target);

    /**
     * @notice Error indicating a failed internal call.
     */
    error FailedInnerCall();

    // FUNCTION

    /**
     * @notice Calls a function on a specified address without transferring value.
     *
     * @param target Address on which the function will be called.
     * @param data Encoded data of the function call.
     *
     * @return returndata Result of the function call.
     *
     * @dev The `target` must be a contract address and this function must be calling
     * `target` with `data` not reverting.
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0);
    }

    /**
     * @notice Calls a function on a specified address with a specified value.
     *
     * @param target Address on which the function will be called.
     * @param data Encoded data of the function call.
     * @param value Value to be sent in the call.
     *
     * @return returndata Result of the function call.
     *
     * @dev This function ensure that the calling contract actually have Ether balance
     * of at least `value` and that the called Solidity function is a `payable`. Should
     * throw if caller does have insufficient balance.
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        if (address(this).balance < value) {
            revert AddressInsufficientBalance(address(this));
        }
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return verifyCallResultFromTarget(target, success, returndata);
    }

    /**
     * @notice Verifies the result of a function call and handles errors if any.
     *
     * @param target Address on which the function was called.
     * @param success Boolean indicating the success of the function call.
     * @param returndata Result data of the function call.
     *
     * @return Result of the function call or reverts with an appropriate error.
     *
     * @dev This help to verify that a low level call to smart-contract was successful
     * and will reverts if the target was not a contract. For unsuccessful call, this
     * will bubble up the revert reason (falling back to {FailedInnerCall}). Should
     * throw if both the returndata and target.code length are 0 when `success` is true.
     */
    function verifyCallResultFromTarget(address target, bool success, bytes memory returndata) internal view returns (bytes memory) {
        if (!success) {
            _revert(returndata);
        } else {
            if (returndata.length == 0 && target.code.length == 0) {
                revert AddressEmptyCode(target);
            }
            return returndata;
        }
    }

    /**
     * @notice Reverts with decoded revert data or FailedInnerCall if no revert
     * data is available.
     *
     * @param returndata Result data of a failed function call.
     *
     * @dev Should throw if returndata length is 0.
     */
    function _revert(bytes memory returndata) private pure {
        if (returndata.length > 0) {
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        } else {
            revert FailedInnerCall();
        }
    }
}

/**
 * @title SafeERC20 Library
 *
 * @notice Collection of functions providing utility for safe operations with
 * ERC20 tokens.
 *
 * @dev This is mainly for the usage of token that throw on failure (when the
 * token contract returns false). Tokens that return no value (and instead revert
 * or throw on failure) are also supported where non-reverting calls are assumed
 * to be a successful transaction.
 */
library SafeERC20 {
    
    // LIBRARY

    using Address for address;

    // ERROR

    /**
     * @notice Error indicating a failed operation during an ERC-20 token transfer.
     *
     * @param token Address of the token contract.
     */
    error SafeERC20FailedOperation(address token);

    // FUNCTION

    /**
     * @notice Safely transfers tokens.
     *
     * @param token ERC20 token interface.
     * @param to Address to which the tokens will be transferred.
     * @param value Amount of tokens to be transferred.
     *
     * @dev Transfer `value` amount of `token` from the calling contract to `to` where
     * non-reverting calls are assumed to be successful if `token` returns no value.
     */
    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeCall(token.transfer, (to, value)));
    }

    /**
     * @notice Calls a function on a token contract and reverts if the operation fails.
     *
     * @param token ERC20 token interface.
     * @param data Encoded data of the function call.
     *
     * @dev This imitates a Solidity high-level call such as a regular function call to
     * a contract while relaxing the requirement on the return value.
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        bytes memory returndata = address(token).functionCall(data);
        if (returndata.length != 0 && !abi.decode(returndata, (bool))) {
            revert SafeERC20FailedOperation(address(token));
        }
    }
}

/********************************************************************************************
  INTERFACE
********************************************************************************************/

/**
 * @title ERC20 Token Standard Interface
 * 
 * @notice Interface of the ERC-20 standard token as defined in the ERC.
 * 
 * @dev See https://eips.ethereum.org/EIPS/eip-20
 */
interface IERC20 {
    
    // EVENT
    
    /**
     * @notice Emitted when `value` tokens are transferred from
     * one account (`from`) to another (`to`).
     * 
     * @param from The address tokens are transferred from.
     * @param to The address tokens are transferred to.
     * @param value The amount of tokens transferred.
     * 
     * @dev The `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @notice Emitted when the allowance of a `spender` for an `owner`
     * is set by a call to {approve}.
     * 
     * @param owner The address allowing `spender` to spend on their behalf.
     * @param spender The address allowed to spend tokens on behalf of `owner`.
     * @param value The allowance amount set for `spender`.
     * 
     * @dev The `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // FUNCTION

    /**
     * @notice Returns the value of tokens in existence.
     * 
     * @return The value of the total supply of tokens.
     * 
     * @dev This should get the total token supply.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Returns the value of tokens owned by `account`.
     * 
     * @param account The address to query the balance for.
     * 
     * @return The token balance of `account`.
     * 
     * @dev This should get the token balance of a specific account.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @notice Moves a `value` amount of tokens from the caller's account to `to`.
     * 
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to be transferred.
     * 
     * @return A boolean indicating whether the transfer was successful or not.
     * 
     * @dev This should transfer tokens to a specified address and emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @notice Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}.
     * 
     * @param owner The address allowing `spender` to spend on their behalf.
     * @param spender The address allowed to spend tokens on behalf of `owner`.
     * 
     * @return The allowance amount for `spender`.
     * 
     * @dev The return value should be zero by default and
     * changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @notice Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
     * 
     * @param spender The address allowed to spend tokens on behalf of the sender.
     * @param value The allowance amount for `spender`.
     * 
     * @return A boolean indicating whether the approval was successful or not.
     * 
     * @dev This should approve `spender` to spend a specified amount of tokens
     * on behalf of the sender and emits an {Approval} event.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @notice Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's allowance.
     * 
     * @param from The address to transfer tokens from.
     * @param to The address to transfer tokens to.
     * @param value The amount of tokens to be transferred.
     * 
     * @return A boolean indicating whether the transfer was successful or not.
     * 
     * @dev This should transfer tokens from one address to another after
     * spending caller's allowance and emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

/**
 * @title ERC20 Token Metadata Interface
 * 
 * @notice Interface for the optional metadata functions of the ERC-20 standard as defined in the ERC.
 * 
 * @dev It extends the IERC20 interface. See https://eips.ethereum.org/EIPS/eip-20
 */
interface IERC20Metadata is IERC20 {

    // FUNCTION
    
    /**
     * @notice Returns the name of the token.
     * 
     * @return The name of the token as a string.
     */
    function name() external view returns (string memory);

    /**
     * @notice Returns the symbol of the token.
     * 
     * @return The symbol of the token as a string.
     */
    function symbol() external view returns (string memory);

    /**
     * @notice Returns the number of decimals used to display the token.
     * 
     * @return The number of decimals as a uint8.
     */
    function decimals() external view returns (uint8);
}

/**
 * @title Common Error Interface
 * 
 * @notice Interface of the common errors not specific to ERC-20 functionalities.
 */
interface ICommonErrors {

    // ERROR

    /**
     * @notice Error indicating that cannot use all current addresses to initiate function.
     */
    error CannotUseAllCurrentAddress();

    /**
     * @notice Error indicating that cannot use all current states to initiate function.
     */
    error CannotUseAllCurrentState();

    /**
     * @notice Error indicating that cannot use all current values to initiate function.
     */
    error CannotUseAllCurrentValue();

    /**
     * @notice Error indicating that the `current` address cannot be used in this context.
     * 
     * @param current Address used in the context.
     */
    error CannotUseCurrentAddress(address current);

    /**
     * @notice Error indicating that the `current` state cannot be used in this context.
     * 
     * @param current Boolean state used in the context.
     */
    error CannotUseCurrentState(bool current);

    /**
     * @notice Error indicating that the `current` value cannot be used in this context.
     * 
     * @param current Value used in the context.
     */
    error CannotUseCurrentValue(uint256 current);

    /**
     * @notice Error indicating that the `invalid` address provided is not a valid address for this context.
     * 
     * @param invalid Address used in the context.
     */
    error InvalidAddress(address invalid);

    /**
     * @notice Error indicating that the `invalid` value provided is not a valid value for this context.
     * 
     * @param invalid Value used in the context.
     */
    error InvalidValue(uint256 invalid);
}

/**
 * @title Revenue Share Interface
 * 
 * @notice Interface of the revenue share contract utilised within the ecosystem.
 */
interface IRevenueShare {

    // FUNCTION

    /**
     * @notice Allow deposits to be made along with the creation of new reward pool.
     */
    function deposit() external payable;

    /**
     * @notice Add the share eligible for dividend after token buy transaction.
     * 
     * @param holder The address of the holder.
     * @param amount The amount being transacted.
     */
    function addShare(address holder, uint256 amount) external;

    /**
     * @notice Remove the share eligible for dividend after token transfer or sell transaction.
     * 
     * @param holder The address of the holder.
     * @param amount The amount being transacted.
     */
    function removeShare(address holder, uint256 amount) external;
}

/********************************************************************************************
  ACCESS
********************************************************************************************/

/**
 * @title Ownable Contract
 * 
 * @notice Abstract contract module implementing ownership functionality through
 * inheritance as a basic access control mechanism, where there is an owner account
 * that can be granted exclusive access to specific functions.
 * 
 * @dev The initial owner is set to the address provided by the deployer and can
 * later be changed with {transferOwnership}.
 */
abstract contract Ownable {

    // DATA

    address private _owner;

    // MODIFIER

    /**
     * @notice Modifier that allows access only to the contract owner.
     *
     * @dev Should throw if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    // ERROR

    /**
     * @notice Error indicating that the `account` is not authorized to perform an operation.
     * 
     * @param account Address used to perform the operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @notice Error indicating that the provided `owner` address is invalid.
     * 
     * @param owner Address used to perform the operation.
     * 
     * @dev Should throw if called by an invalid owner account such as address(0) as an example.
     */
    error OwnableInvalidOwner(address owner);

    // CONSTRUCTOR

    /**
     * @notice Initializes the contract setting the `initialOwner` address provided by
     * the deployer as the initial owner.
     * 
     * @param initialOwner The address to set as the initial owner.
     *
     * @dev Should throw an error if called with address(0) as the `initialOwner`.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }
    
    // EVENT
    
    /**
     * @notice Emitted when ownership of the contract is transferred.
     * 
     * @param previousOwner The address of the previous owner.
     * @param newOwner The address of the new owner.
     */
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // FUNCTION

    /**
     * @notice Get the address of the smart contract owner.
     * 
     * @return The address of the current owner.
     *
     * @dev Should return the address of the current smart contract owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }
    
    /**
     * @notice Checks if the caller is the owner and reverts if not.
     * 
     * @dev Should throw if the sender is not the current owner of the smart contract.
     */
    function _checkOwner() internal view virtual {
        if (owner() != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }
    
    /**
     * @notice Allows the current owner to renounce ownership and make the
     * smart contract ownerless.
     * 
     * @dev This function can only be called by the current owner and will
     * render all `onlyOwner` functions inoperable.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    
    /**
     * @notice Allows the current owner to transfer ownership of the smart contract
     * to `newOwner` address.
     * 
     * @param newOwner The address to transfer ownership to.
     *
     * @dev This function can only be called by the current owner and will render
     * all `onlyOwner` functions inoperable to him/her. Should throw if called with
     * address(0) as the `newOwner`.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }
    
    /**
     * @notice Internal function to transfer ownership of the smart contract
     * to `newOwner` address.
     * 
     * @param newOwner The address to transfer ownership to.
     *
     * @dev This function replace current owner address stored as _owner with 
     * the address of the `newOwner`.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/**
 * @title Auth Contract
 * 
 * @notice Abstract contract module for managing authorization.
 *
 * @dev This contract provides functionality for authorizing and unauthorizing accounts.
 */
abstract contract Auth is Ownable {
    
    // MAPPING

    mapping(address => bool) public authorization;

    // MODIFIER

    modifier authorized() {
        _checkAuthorized();
        _;
    }

    // ERROR

    /**
     * @notice Error indicating that the account is not authorized.
     * 
     * @dev Should throw if called when the account was not authorized.
     */
    error InvalidAuthorizedAccount(address account);

    /**
     * @notice Error indicating that current state is being used.
     * 
     * @dev Should throw if called when the current state is being used.
     */
    error CurrentAuthorizedState(address account, bool state);
    
    // CONSTRUCTOR

    constructor(
        address initialOwner
    ) Ownable(initialOwner) {
        authorize(initialOwner);
        if (initialOwner != msg.sender) {
            authorize(msg.sender);
        }
    }

    // EVENT
    
    /**
     * @notice Emitted when the account's authorization status was updated.
     * 
     * @param state The new state being used for the account.
     * @param authorizedAccount The address of the account being updated.
     * @param caller The address of the caller who update the account.
     * @param timestamp The timestamp when the account was updated.
     */
    event UpdateAuthorizedAccount(address authorizedAccount, address caller, bool state, uint256 timestamp);

    // FUNCTION

    /**
     * @notice Checks if the caller is authorized.
     * 
     * @dev This function checks whether the caller is authorized by verifying their
     * presence in the authorization mapping. If the caller is not authorized, the
     * function reverts with an appropriate error message.
     */
    function _checkAuthorized() internal view virtual {
        if (!authorization[msg.sender]) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    /**
     * @notice Authorizes an account.
     * 
     * @param account The address of the account to be authorized.
     * 
     * @dev This function authorizes the specified account by updating the authorization mapping.
     * It checks if the account address is valid and not equal to address(0) or address(0xdead).
     */
    function authorize(address account) public virtual onlyOwner {
        if (account == address(0) || account == address(0xdead)) {
            revert InvalidAuthorizedAccount(account);
        }
        _authorization(account, msg.sender, true);
    }

    /**
     * @notice Unauthorizes an account.
     * 
     * @param account The address of the account to be unauthorized.
     * 
     * @dev This function unauthorizes the specified account by updating the authorization mapping.
     * It checks if the account address is valid and not equal to address(0) or address(0xdead).
     */
    function unauthorize(address account) public virtual onlyOwner {
        if (account == address(0) || account == address(0xdead)) {
            revert InvalidAuthorizedAccount(account);
        }
        _authorization(account, msg.sender, false);
    }

    /**
     * @notice Internal function for managing authorization status.
     * 
     * @param account The address of the account to be authorized or unauthorized.
     * @param caller The address of the caller authorizing or unauthorizing the account.
     * @param state The desired authorization state (true for authorized, false for unauthorized).
     * 
     * @dev This function updates the authorization mapping for the specified account and emits an
     * `UpdateAuthorizedAccount` event. It checks if the current authorization state matches the
     * desired state before updating.
     */
    function _authorization(address account, address caller, bool state) internal virtual {
        if (authorization[account] == state) {
            revert CurrentAuthorizedState(account, state);
        }
        authorization[account] = state;
        emit UpdateAuthorizedAccount(account, caller, state, block.timestamp);
    }
}

/********************************************************************************************
  SECURITY
********************************************************************************************/

/**
 * @title Pausable Contract
 * 
 * @notice Abstract contract module implementing pause functionality through
 * inheritance as a basic security mechanism, where there certain functions
 * that can be paused and unpaused.
 */
abstract contract Pausable {

    // DATA

    bool private _paused;

    // ERROR

    /**
     * @notice Error thrown when an action is attempted in an enforced pause.
     */
    error EnforcedPause();

    /**
     * @notice Error thrown when an action is attempted without the expected pause.
     */
    error ExpectedPause();

    // MODIFIER

    /**
     * @notice Modifier ensure functions are called when the contract is
     * not paused.
     * 
     * @dev Should throw if called when the contract is paused.
     */
    modifier whenNotPaused() {
        _requireNotPaused();
        _;
    }

    /**
     * @notice Modifier ensure functions are called when the contract is
     * paused.
     * 
     * @dev Should throw if called when the contract is not paused.
     */
    modifier whenPaused() {
        _requirePaused();
        _;
    }

    // CONSTRUCTOR

    /**
     * @notice Initializes the contract setting the `_paused` state as false.
     */
    constructor() {
        _paused = false;
    }

    // EVENT
    
    /**
     * @notice Emitted when the contract is paused.
     * 
     * @param account The address that initiate the function.
     */
    event Paused(address account);

    /**
     * @notice Emitted when the contract is unpaused.
     * 
     * @param account The address that initiate the function.
     */
    event Unpaused(address account);

    // FUNCTION

    /**
     * @notice Returns the current paused state of the contract.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @notice Function to pause the contract.
     * 
     * @dev This function is accessible externally when not paused.
     */
    function pause() public virtual whenNotPaused {
        _pause();
    }

    /**
     * @notice Function to unpause the contract.
     * 
     * @dev This function is accessible externally when paused.
     */
    function unpause() public virtual whenPaused {
        _unpause();
    }

    /**
     * @notice Internal function to revert if the contract is not paused.
     * 
     * @dev Throws when smart contract is paused.
     */
    function _requireNotPaused() internal view virtual {
        if (paused()) {
            revert EnforcedPause();
        }
    }

    /**
     * @notice Internal function to revert if the contract is paused.
     * 
     * @dev Throws when smart contract is not paused.
     */
    function _requirePaused() internal view virtual {
        if (!paused()) {
            revert ExpectedPause();
        }
    }

    /**
     * @notice Internal function to pause the contract.
     * 
     * @dev This function emits {Paused} event.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @notice Internal function to unpause the contract.
     * 
     * @dev This function emits {Unpaused} event.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }
}

/********************************************************************************************
  DISTRIBUTOR
********************************************************************************************/

/**
 * @title BRO Distributor Contract
 *
 * @notice BRO Distributor is the smart contract used for the revenue share system within
 * the BRO ecosystem.
 * 
 * @dev Implements RevenueShare and CommonError interfaces, and extends Auth contract while
 * at the same time implementing the Pausable logic.
 */
contract Distributor is Auth, Pausable, ICommonErrors, IRevenueShare {

    // LIBRARY

    using SafeERC20 for IERC20;
    using Address for address;

    // DATA

    struct PenaltyHistory {
        address holder;
        uint256 penaltyTime;
        uint256 totalReward;
        uint256 startIndex;
        uint256 lastIndex;
    }

    struct RewardHistory {
        address holder;
        uint256 distributedTime;
        uint256 totalReward;
        uint256 startIndex;
        uint256 lastIndex;
    }

    struct RewardInfo {
        uint256 createTime;
        uint256 amountAdded;
        uint256 shareEligible;
        uint256 rewardsPerShare;
        uint256 rewardsPerShareAccuracyFactor;
    }

    struct ShareInfo {
        uint256 lastTxn;
        uint256 cooldown;
        uint256 shares;
        uint256 startPoolIndex;
        uint256 eligibleTime;
    }

    address public projectOwner;
    address public tokenAddress;

    uint256 public lastTally = 0;
    uint256 public rewardHistoryIndex = 0;
    uint256 public penaltyHistoryIndex = 0;
    uint256 public totalHolders = 0;
    uint256 public totalShares = 0;
    uint256 public totalRewardPool = 0;
    uint256 public allocatedFund = 0;
    uint256 public distributedFund = 0;
    uint256 public accuracyFactor = 0;
    uint256 public lastRewardAddedTimestamp = 0;
    uint256 public maximumAmountPerEpoch = 18_000 ether;
    uint256 public minimumRewardRequired = 0.1 ether;
    uint256 public minimumForRewardPool = 10 ether;
    uint256 public minimumBalanceEligible = 3_000 ether;
    uint256 public cooldownTime = 7 hours;

    bool public justCreatePool = false;
    bool public useAddShareCooldown = false;
    bool public useRemoveShareCooldown = true;

    // MAPPING
    
    mapping(address account => ShareInfo) public userEligibility;
    mapping(address account => uint256) public remainingTransactable;
    mapping(address account => uint256) public holderIndex;
    mapping(uint256 holderId => address) public holderAtIndex;
    mapping(uint256 poolId => RewardInfo) public rewardPool;
    mapping(uint256 historyId => RewardHistory) public rewardHistory;
    mapping(address account => uint256) public userRewardHistoryIndex;
    mapping(address account => mapping(uint256 index => uint256)) public userRewardHistory;
    mapping(uint256 penaltyId => PenaltyHistory) public penaltyHistory;
    mapping(address account => uint256) public userPenaltyHistoryIndex;
    mapping(address account => mapping(uint256 index => uint256)) public userPenaltyHistory;

    // ERROR

    /**
     * @notice Error indicating that the native cannot be withdrawn from the smart contract.
     */
    error CannotWithdrawNative();

    /**
     * @notice Error indicating that the native fund in the smart contract is insufficient.
     */
    error InsufficientFund();

    /**
     * @notice Error indicating that the receiver cannot initiate transfer of Ether.
     * 
     * @dev Should throw if called by the receiver address.
     */
    error ReceiverCannotInitiateTransferEther();

    /**
     * @notice Error indicating cooldown has not end.
     */
    error WaitForCooldown(uint256 currentTime, uint256 endTime, uint256 timeLeft);

    /**
     * @notice Error indicating that the function not initiated by token contract.
     * 
     * @dev Should throw if called by address other than token.
     */
    error NotInitiatedByToken(address caller);

    /**
     * @notice Error indicating that the `sender` has insufficient `balance` for the operation.
     * 
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     *
     * @dev The `needed` value is required to inform user on the needed amount.
     */
    error InsufficientBalance(address sender, uint256 balance, uint256 needed);

    // MODIFIER
    
    /**
     * @notice Modifier to only allow token to initiate the function.
     */
    modifier onlyToken() {
        if (tokenAddress != msg.sender) {
            revert NotInitiatedByToken(msg.sender);
        }
        _;
    }

    // CONSTRUCTOR

    /**
     * @notice Constructs the distributor contract and initializes all important settings.
     */
    constructor(
        address initialOwner,
        address token
    ) Auth (
        msg.sender
    ) payable {
        if (initialOwner == address(0) || initialOwner == address(0xdead)) {
            revert InvalidAddress(initialOwner);
        }
        if (initialOwner != msg.sender) {
            authorize(initialOwner);
        }
        tokenAddress = token;
        projectOwner = initialOwner;
        accuracyFactor = (1 ether) * (1 ether);
    }

    // EVENT

    /**
     * @notice Emitted when the value of a feature is updated.
     * 
     * @param valueType The type of value being updated.
     * @param oldValue The previous status before the update.
     * @param newValue The new status after the update.
     * @param caller The address of the caller who updated the value.
     * @param timestamp The timestamp when the update occurred.
     */
    event UpdateValue(string valueType, uint256 oldValue, uint256 newValue, address caller, uint256 timestamp);

    /**
     * @notice Emitted when the state of a feature is updated.
     * 
     * @param stateType The type of state being updated.
     * @param oldState The previous status before the update.
     * @param newState The new status after the update.
     * @param caller The address of the caller who updated the state.
     * @param timestamp The timestamp when the update occurred.
     */
    event UpdateState(string stateType, bool oldState, bool newState, address caller, uint256 timestamp);

    /**
     * @notice Emitted when the claiming reward.
     * 
     * @param holder The address of the holder who claimed the reward.
     * @param rewardClaimed The total amount of reward claimed.
     * @param startIndex The reward pool index where claim start occuring.
     * @param lastIndex The reward pool index where claim stop occuring.
     * @param timestamp The timestamp when the claim occurred.
     */
    event RewardClaimed(address holder, uint256 rewardClaimed, uint256 startIndex, uint256 lastIndex, uint256 timestamp);

    /**
     * @notice Emitted when taking penalty.
     * 
     * @param holder The address of the holder who received the penalty.
     * @param penaltyTaken The total amount of penalty taken.
     * @param startIndex The reward pool index where penalty start occuring.
     * @param lastIndex The reward pool index where penalty stop occuring.
     * @param timestamp The timestamp when the penalty occurred.
     */
    event PenaltyTaken(address holder, uint256 penaltyTaken, uint256 startIndex, uint256 lastIndex, uint256 timestamp);

    /**
     * @notice Emitted when deposit for reward pool was created on the contract.
     * 
     * @param poolId The id of the reward pool created.
     * @param rewardAdded The amount of reward added for the pool.
     * @param caller The address that triggered the reward pool creation.
     * @param timestamp The timestamp when reward pool was created.
     */
    event RewardDeposited(uint256 poolId, uint256 rewardAdded, address caller, uint256 timestamp);

    /**
     * @notice Emitted when share was added after a user buy token.
     * 
     * @param holder The address of the user whose share is being updated.
     * @param amount The amount of share being added for the user.
     * @param caller The address that triggered the share update.
     * @param timestamp The timestamp when share was updated.
     */
    event AddShare(address holder, uint256 amount, address caller, uint256 timestamp);

    /**
     * @notice Emitted when share was removed after a user sell or transfer token.
     * 
     * @param holder The address of the user whose share is being updated.
     * @param amount The amount of share being removed for the user.
     * @param caller The address that triggered the share update.
     * @param timestamp The timestamp when share was updated.
     */
    event RemoveShare(address holder, uint256 amount, address caller, uint256 timestamp);

    /**
     * @notice Emitted when reward distribution was updated to balance out the difference.
     * 
     * @param desiredAmount The amount to be expected.
     * @param oldAmount The amount currently in use.
     * @param newAmount The amount after the update.
     * @param caller The address that triggered the update.
     * @param timestamp The timestamp for the update.
     */
    event TallyDistribution(uint256 desiredAmount, uint256 oldAmount, uint256 newAmount, address caller, uint256 timestamp);

    // FUNCTION

    /* General */
    
    /**
     * @notice Allows the contract to receive Ether.
     * 
     * @dev This is a required feature to have in order to allow the smart contract
     * to be able to receive ether from the swap.
     */
    receive() external payable {}

    /**
     * @notice Withdraws tokens or Ether from the contract to a specified address.
     * 
     * @param token The address of the token to withdraw.
     * @param amount The amount of tokens or Ether to withdraw.
     * 
     * @dev You need to use address(0) as `tokenAddress` to withdraw Ether and
     * use 0 as `amount` to withdraw the whole balance amount in the smart contract.
     * Anyone can trigger this function to send the fund to the `feeReceiver`.
     * Only `feeReceiver` address will not be able to trigger this function to
     * withdraw Ether from the smart contract by himself/herself. Should throw if try
     * to withdraw any amount of native token from the smart contract. Distribution
     * of native token can only be done through autoRedeem function.
     */
    function wTokens(address token, uint256 amount) external {
        uint256 locked = allocatedFund > distributedFund ? allocatedFund - distributedFund : 0;
        uint256 toTransfer = amount;
        address receiver = projectOwner;
        
        if (token == address(0)) {
            if (locked >= address(this).balance) {
                revert CannotWithdrawNative();
            }
            if (amount > address(this).balance - locked) {
                revert InsufficientFund();
            }
            if (msg.sender == receiver) {
                revert ReceiverCannotInitiateTransferEther();
            }
            if (amount == 0) {
                toTransfer = address(this).balance - locked;
            }
            payable(receiver).transfer(toTransfer);
        } else {
            if (amount == 0) {
                toTransfer = IERC20(token).balanceOf(address(this));
            }
            IERC20(token).safeTransfer(receiver, toTransfer);
        }
    }

    /**
     * @notice A function to adjust and tally the difference between amount of reward
     * distributed to amount of reward allocated as the result from the nature of how
     * calculation was carried out in Solidity.
     * 
     * @dev Should throw if using an invalid value.
     */
    function tallyDistribution(uint256 amount) external onlyOwner {
        if (amount < 1 && amount > 5) {
            revert InvalidValue(amount);
        }
        if (lastTally + 1 hours > block.timestamp) {
            revert WaitForCooldown(block.timestamp, lastTally + 1 hours, (lastTally + 1 hours) - block.timestamp);
        }
        uint256 oldAmount = distributedFund;
        distributedFund += amount;
        lastTally = block.timestamp;
        emit TallyDistribution(allocatedFund, oldAmount, distributedFund + amount, msg.sender, block.timestamp);
    }

    /* Check */

    /**
     * @notice Checks if using current state.
     * 
     * @dev Should throw if using current state.
     */
    function checkCurrentState(bool newState, bool current) internal pure {
        if (newState == current) {
            revert CannotUseCurrentState(newState);
        }
    }

    /**
     * @notice Checks if using current value.
     * 
     * @dev Should throw if using current value.
     */
    function checkCurrentValue(uint256 newValue, uint256 current) internal pure {
        if (newValue == current) {
            revert CannotUseCurrentValue(newValue);
        }
    }
    
    /**
     * @notice Checks if using invalid value.
     * 
     * @dev Should throw if using invalid value.
     */
    function checkInvalidValue(uint256 newValue, uint256 invalid) internal pure {
        if (newValue == invalid) {
            revert InvalidValue(newValue);
        }
    }

    /**
     * @notice Checks if using current address.
     * 
     * @dev Should throw if using current address.
     */
    function checkCurrentAddress(address newAddress, address current) internal pure {
        if (newAddress == current) {
            revert CannotUseCurrentAddress(newAddress);
        }
    }
    
    /**
     * @notice Checks if using invalid address.
     * 
     * @dev Should throw if using invalid address.
     */
    function checkInvalidAddress(address newAddress, address invalid) internal pure {
        if (newAddress == invalid) {
            revert InvalidAddress(newAddress);
        }
    }

    /**
     * @notice Checks the transaction involve cooldown and penalty.
     * 
     * @param holder The address that will be doing the transaction.
     * @param amount The amount that will be used for the transaction.
     * 
     * @return The state to show if the transaction will exceed amount allowed per reward epoch.
     * @return The duration left for cooldown.
     * @return The amount left that was allowed to be transacted per reward epoch.
     */
    function checkCooldownPenalty(address holder, uint256 amount) public view returns (bool, uint256, uint256) {
        uint256 lastTxn = userEligibility[holder].lastTxn;
        uint256 cooldown = userEligibility[holder].cooldown;
        bool exceed = false;

        if (
            (
                cooldown < 1 ||
                block.timestamp - lastTxn > cooldownTime ||
                block.timestamp - lastTxn >= cooldown
            ) && (
                amount <= maximumAmountPerEpoch &&
                amount <= remainingTransactable[holder]
            )
        ) {
            return (
                exceed, 
                block.timestamp - lastTxn > cooldownTime ||
                block.timestamp - lastTxn >= cooldown ? 
                    cooldownTime
                :
                    cooldown - (block.timestamp - lastTxn), 
                remainingTransactable[holder] > amount ? 
                    remainingTransactable[holder] - amount 
                :
                    0
            );
        } else {
            exceed = remainingTransactable[holder] < amount;
            return (
                exceed, 
                cooldown - (block.timestamp - lastTxn), 
            remainingTransactable[holder] > amount ? 
                remainingTransactable[holder] - amount 
            :
                0
            );
        }
    }

    /* Update */

    /**
     * @notice Updates the value of maximumAmountPerEpoch.
     * 
     * @param newValue The new value of maximumAmountPerEpoch to be set.
     * 
     * @dev This function will emits the UpdateValue event.
     */
    function updateMaximumAmountPerEpoch(uint256 newValue) external authorized {
        if (newValue < 50 ether) {
            revert InvalidValue(newValue);
        }
        checkCurrentValue(newValue, maximumAmountPerEpoch);
        uint256 oldValue = maximumAmountPerEpoch;
        maximumAmountPerEpoch = newValue;
        emit UpdateValue("maximumAmountPerEpoch", oldValue, newValue, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the value of minimumRewardRequired.
     * 
     * @param newValue The new value of minimumRewardRequired to be set.
     * 
     * @dev This function will emits the UpdateValue event.
     */
    function updateMinimumRewardRequired(uint256 newValue) external authorized {
        if (newValue > 1 ether) {
            revert InvalidValue(newValue);
        }
        checkCurrentValue(newValue, minimumRewardRequired);
        uint256 oldValue = minimumRewardRequired;
        minimumRewardRequired = newValue;
        emit UpdateValue("minimumRewardRequired", oldValue, newValue, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the value of minimumForRewardPool.
     * 
     * @param newValue The new value of minimumForRewardPool to be set.
     * 
     * @dev This function will emits the UpdateValue event.
     */
    function updateMinimumForRewardPool(uint256 newValue) external authorized {
        if (newValue < 1 ether) {
            revert InvalidValue(newValue);
        }
        checkCurrentValue(newValue, minimumForRewardPool);
        uint256 oldValue = minimumForRewardPool;
        minimumForRewardPool = newValue;
        emit UpdateValue("minimumForRewardPool", oldValue, newValue, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the value of minimumBalanceEligible.
     * 
     * @param newValue The new value of minimumBalanceEligible to be set.
     * 
     * @dev This function will emits the UpdateValue event.
     */
    function updateMinimumBalanceEligible(uint256 newValue) external authorized {
        if (newValue < 0) {
            revert InvalidValue(newValue);
        }
        checkCurrentValue(newValue, minimumBalanceEligible);
        uint256 oldValue = minimumBalanceEligible;
        minimumBalanceEligible = newValue;
        emit UpdateValue("minimumBalanceEligible", oldValue, newValue, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the value of cooldownTime.
     * 
     * @param newValue The new value of cooldownTime to be set.
     * 
     * @dev This function will emits the UpdateValue event.
     */
    function updateCooldownTime(uint256 newValue) external authorized {
        if (newValue < 30 minutes || newValue > 7 days) {
            revert InvalidValue(newValue);
        }
        checkCurrentValue(newValue, cooldownTime);
        uint256 oldValue = cooldownTime;
        cooldownTime = newValue;
        emit UpdateValue("cooldownTime", oldValue, newValue, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the state of useAddShareCooldown.
     * 
     * @param newState The new state of useAddShareCooldown to be set.
     * 
     * @dev This function will emits the UpdateState event.
     */
    function updateUseAddShareCooldown(bool newState) external authorized {
        checkCurrentState(newState, useAddShareCooldown);
        bool oldState = useAddShareCooldown;
        useAddShareCooldown = newState;
        emit UpdateState("useAddShareCooldown", oldState, newState, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the state of useRemoveShareCooldown.
     * 
     * @param newState The new state of useRemoveShareCooldown to be set.
     * 
     * @dev This function will emits the UpdateState event.
     */
    function updateUseRemoveShareCooldown(bool newState) external authorized {
        checkCurrentState(newState, useRemoveShareCooldown);
        bool oldState = useRemoveShareCooldown;
        useRemoveShareCooldown = newState;
        emit UpdateState("useRemoveShareCooldown", oldState, newState, msg.sender, block.timestamp);
    }

    /* Reward */

    /**
     * @notice Allow deposits to be made along with the creation of new reward pool.
     * 
     * @dev This function will allow new reward pool to be created if the conditions were met.
     */
    function deposit() external payable override whenNotPaused {
        if (allocatedFund < distributedFund) {
            uint256 diff = distributedFund - allocatedFund;
            distributedFund -= diff;
        }

        uint256 rewardBalance = allocatedFund > distributedFund ? allocatedFund - distributedFund : 0;
        uint256 current = address(this).balance - rewardBalance;

        if (
            totalHolders > 0 &&
            totalShares > 0 &&
            current >= minimumForRewardPool &&
            lastRewardAddedTimestamp + cooldownTime <= block.timestamp
        ) {
            justCreatePool = true;
            totalRewardPool = totalRewardPool + 1;
            allocatedFund = allocatedFund + current;
            lastRewardAddedTimestamp = block.timestamp;
            rewardPool[totalRewardPool].createTime = block.timestamp;
            rewardPool[totalRewardPool].amountAdded = current;
            rewardPool[totalRewardPool].shareEligible = totalShares;
            rewardPool[totalRewardPool].rewardsPerShare = current * accuracyFactor / totalShares;
            rewardPool[totalRewardPool].rewardsPerShareAccuracyFactor = accuracyFactor;
            emit RewardDeposited(totalRewardPool, current, msg.sender, block.timestamp);
        }
    }

    /**
     * @notice Checks all pending rewards for a specific users.
     * 
     * @param holder The address of the user being check.
     * 
     * @dev This function will loop the check from the user's current start pool index.
     */
    function checkAllPendingRewards(address holder) public view returns (uint256) {
        if (holderIndex[holder] < 1 || userEligibility[holder].startPoolIndex > totalRewardPool) {
            return 0;
        }
        return checkPendingRewards(holder, totalRewardPool);
    }

    /**
     * @notice Checks all pending rewards for a specific users from account start index to specific end index.
     * 
     * @param holder The address of the user being check.
     * @param endIndex The last index to check.
     * 
     * @dev This function will loop the check from the given reward pool index range.
     */
    function checkPendingRewards(address holder, uint256 endIndex) public view returns (uint256) {
        uint256 pending = 0;
        uint256 startIndex = userEligibility[holder].startPoolIndex;
        if (endIndex > totalRewardPool) {
            endIndex = totalRewardPool;
        }
        for (uint256 i = startIndex; i < endIndex + 1; i++) {
            uint256 reward = (userEligibility[holder].shares * rewardPool[i].rewardsPerShare) / rewardPool[i].rewardsPerShareAccuracyFactor;
            pending += reward;
        }
        return pending;
    }

    /**
     * @notice Allow users to manually initiate the reward claim functionality.
     * 
     * @dev This function will check the pending rewards from eligible pool and distribute the amount.
     */
    function manualClaimRewards() external {
        claimRewards(msg.sender);
    }

    /**
     * @notice Initiate the reward claim functionality internally.
     * 
     * @dev This function will check the pending rewards from eligible pool and distribute the amount.
     */
    function claimRewards(address holder) public {
        uint256 startIndex = userEligibility[holder].startPoolIndex;
        uint256 lastIndex = startIndex;
        if (lastIndex > totalRewardPool) {
            return;
        }
        if (startIndex < 1) {
            return;
        }
        while (
            rewardPool[lastIndex].createTime + cooldownTime < block.timestamp &&
            lastIndex < totalRewardPool + 1
        ) {
            lastIndex++;
        }

        uint256 pending = checkPendingRewards(holder, lastIndex - 1);
        if (minimumRewardRequired <= pending) {
            userEligibility[holder].startPoolIndex = lastIndex;
            distributedFund += pending;
            rewardHistoryIndex++;
            rewardHistory[rewardHistoryIndex].holder = holder;
            rewardHistory[rewardHistoryIndex].distributedTime = block.timestamp;
            rewardHistory[rewardHistoryIndex].totalReward = pending;
            rewardHistory[rewardHistoryIndex].startIndex = startIndex;
            rewardHistory[rewardHistoryIndex].lastIndex = lastIndex - 1;
            userRewardHistoryIndex[holder] += 1;
            userRewardHistory[holder][userRewardHistoryIndex[holder]] = rewardHistoryIndex;
            payable(holder).transfer(pending);
            emit RewardClaimed(holder, pending, startIndex, lastIndex, block.timestamp);
        }
    }
    
    /* Distributor */

    /**
     * @notice Add the share eligible for dividend after token buy transaction.
     * 
     * @param holder The address of the holder.
     * @param amount The amount being transacted.
     */
    function addShare(address holder, uint256 amount) external override onlyToken whenNotPaused {
        uint256 oldShare = userEligibility[holder].shares;
        uint256 newShare = IERC20(tokenAddress).balanceOf(holder) + amount;
        bool alreadyEligible = oldShare >= minimumBalanceEligible;
        bool isEligible = IERC20(tokenAddress).balanceOf(holder) + amount >= minimumBalanceEligible;
        if (isEligible) {
            if (oldShare < 1) {
                addHolder(holder);
            }
            if (oldShare > 0) {
                if (totalRewardPool > 0 && userEligibility[holder].startPoolIndex > 0 && userEligibility[holder].startPoolIndex < totalRewardPool + 1) {
                    claimRewards(holder);
                }
            }
            userEligibility[holder].shares = newShare;
            totalShares = totalShares - oldShare + newShare;
            emit AddShare(holder, amount, msg.sender, block.timestamp);
        }
        if (alreadyEligible && useAddShareCooldown) {
            checkPenalty(holder, amount, false, false);
        }
    }

    /**
     * @notice Remove the share eligible for dividend after token transfer or sell transaction.
     * 
     * @param holder The address of the holder.
     * @param amount The amount being transacted.
     */
    function removeShare(address holder, uint256 amount) external override onlyToken whenNotPaused {
        uint256 oldShare = userEligibility[holder].shares;
        uint256 newShare = IERC20(tokenAddress).balanceOf(holder) - amount;
        bool alreadyEligible = oldShare >= minimumBalanceEligible;
        bool isEligible = IERC20(tokenAddress).balanceOf(holder) - amount >= minimumBalanceEligible;
        bool poolUpdated = false;
        if (justCreatePool) {
            if (rewardPool[totalRewardPool].createTime + cooldownTime >= block.timestamp) {
                uint256 newTotalShare = rewardPool[totalRewardPool].shareEligible - amount;
                rewardPool[totalRewardPool].shareEligible = newTotalShare;
                rewardPool[totalRewardPool].rewardsPerShare = rewardPool[totalRewardPool].amountAdded * accuracyFactor / newTotalShare;
                poolUpdated = true;
            }
            justCreatePool = false;
        }
        if (alreadyEligible && totalRewardPool > 0 && userEligibility[holder].startPoolIndex > 0 && userEligibility[holder].startPoolIndex < totalRewardPool + 1) {
            claimRewards(holder);
        }
        if (isEligible) {
            userEligibility[holder].shares = newShare;
            totalShares = totalShares - oldShare + newShare;
            emit RemoveShare(holder, amount, msg.sender, block.timestamp);
        }
        if (!isEligible) {
            totalShares = totalShares - oldShare;
            userEligibility[holder].shares = 0;
            removeHolder(holder);
            emit RemoveShare(holder, oldShare, msg.sender, block.timestamp);
        }
        if (alreadyEligible && useRemoveShareCooldown) {
            checkPenalty(holder, amount, true, poolUpdated);
        }
    }

    /**
     * @notice Check and take action if penalty incurred on the transaction.
     * 
     * @param holder The address of the holder.
     * @param amount The amount being transacted.
     * @param removal The status of amount transacted whether it is removed or added.
     * @param poolUpdated The status on whether latest reward pool has been updated.
     */
    function checkPenalty(address holder, uint256 amount, bool removal, bool poolUpdated) internal {
        uint256 lastTxn = userEligibility[holder].lastTxn;
        uint256 cooldown = userEligibility[holder].cooldown;
        bool exceed = false;
        
        if (
            cooldown < 1 ||
            block.timestamp - lastTxn > cooldownTime ||
            block.timestamp - lastTxn >= userEligibility[holder].cooldown
        ) {
            userEligibility[holder].cooldown = cooldownTime;
            remainingTransactable[holder] = maximumAmountPerEpoch;
        } else {
            exceed = remainingTransactable[holder] < amount;
            userEligibility[holder].cooldown -= (block.timestamp - lastTxn);
            remainingTransactable[holder] = remainingTransactable[holder] > amount ? remainingTransactable[holder] - amount : 0;
        }

        userEligibility[holder].lastTxn = block.timestamp;

        uint256 startIndex = userEligibility[holder].startPoolIndex;
        uint256 lastIndex = startIndex;

        while (
            rewardPool[lastIndex].createTime + cooldownTime > block.timestamp &&
            lastIndex < totalRewardPool + 1
        ) {
            lastIndex++;
        }

        if (removal && startIndex < lastIndex) {
            uint256 count = startIndex;
            while (count < lastIndex) {
                if (!poolUpdated) {
                    uint256 newTotalShare = rewardPool[count].shareEligible - amount;
                    rewardPool[count].shareEligible = newTotalShare;
                    rewardPool[count].rewardsPerShare = rewardPool[count].amountAdded * accuracyFactor / newTotalShare;
                } else {
                    if (count < lastIndex - 1) {
                        uint256 newTotalShare = rewardPool[count].shareEligible - amount;
                        rewardPool[count].shareEligible = newTotalShare;
                        rewardPool[count].rewardsPerShare = rewardPool[count].amountAdded * accuracyFactor / newTotalShare;
                    }
                }
                count++;
            }
        }

        if (exceed) {
            uint256 pending = checkPendingRewards(holder, lastIndex - 1);
            userEligibility[holder].startPoolIndex = lastIndex;
            distributedFund += pending;

            penaltyHistoryIndex++;
            penaltyHistory[penaltyHistoryIndex].holder = holder;
            penaltyHistory[penaltyHistoryIndex].penaltyTime = block.timestamp;
            penaltyHistory[penaltyHistoryIndex].totalReward = pending;
            penaltyHistory[penaltyHistoryIndex].startIndex = startIndex;
            penaltyHistory[penaltyHistoryIndex].lastIndex = lastIndex - 1;
            userPenaltyHistoryIndex[holder] += 1;
            userPenaltyHistory[holder][userPenaltyHistoryIndex[holder]] = penaltyHistoryIndex;
            emit PenaltyTaken(holder, pending, startIndex, lastIndex, block.timestamp);
        }
    }

    /* Holders */

    /*
     * @notice Adds a holder to the list of eligible holder.
     * 
     * @param holder The address of the holder being added.
     * 
     * @dev This function is internal and should only be called within the contract.
     */
    function addHolder(address holder) internal {
        totalHolders++;
        holderAtIndex[totalHolders] = holder;
        holderIndex[holder] = totalHolders;
        userEligibility[holder].eligibleTime = block.timestamp;
        userEligibility[holder].startPoolIndex = totalRewardPool + 1;
    }

    /**
     * @notice Removes a holder from the list of eligible holder.
     * 
     * @param holder The address of the holder being removed.
     * 
     * @dev This function is internal and should only be called within the contract.
     */
    function removeHolder(address holder) internal {
        uint256 currentIndex = holderIndex[holder];
        address lastHolder = holderAtIndex[totalHolders];
        
        holderIndex[lastHolder] = currentIndex;
        holderAtIndex[currentIndex] = lastHolder;
        holderIndex[holder] = 0;
        holderAtIndex[totalHolders] = address(0);
        userEligibility[holder].eligibleTime = 0;
        userEligibility[holder].startPoolIndex = 0;

        totalHolders--;
    }
    
    /* Override */
    
    /**
     * @notice Overrides the {transferOwnership} function to update project owner.
     * 
     * @param newOwner The address of the new owner.
     * 
     * @dev Should throw if the `newOwner` is set to the current owner address or address(0xdead).
     * This overrides function is just an extended version of the original {transferOwnership}
     * function. See {Ownable-transferOwnership} for more information.
     */
    function transferOwnership(address newOwner) public override onlyOwner {
        checkCurrentAddress(newOwner, owner());
        checkInvalidAddress(newOwner, address(0xdead));
        projectOwner = newOwner;
        super.transferOwnership(newOwner);
    }
    
    /**
     * @notice Overrides the {pause} function to pause the contract.
     * 
     * @dev This function is accessible externally when not paused only by authorized account.
     */
    function pause() public override whenNotPaused authorized {
        super.pause();
    }

    /**
     * @notice Overrides the {unpause} function to pause the contract.
     * 
     * @dev This function is accessible externally when paused only by authorized account.
     */
    function unpause() public override whenPaused authorized {
        super.unpause();
    }
}