/**
 * ██████  ███████ ██    ██  ██████  ██      ██    ██ ███████ ██  ██████  ███    ██
 * ██   ██ ██      ██    ██ ██    ██ ██      ██    ██     ██  ██ ██    ██ ████   ██
 * ██████  █████   ██    ██ ██    ██ ██      ██    ██   ██    ██ ██    ██ ██ ██  ██
 * ██   ██ ██       ██  ██  ██    ██ ██      ██    ██  ██     ██ ██    ██ ██  ██ ██
 * ██   ██ ███████   ████    ██████  ███████  ██████  ███████ ██  ██████  ██   ████
 * 
 * @title EternalAI
 * 
 * @notice This is a smart contract developed by Revoluzion for EternalAI.
 * 
 * @dev This smart contract was developed based on the general
 * OpenZeppelin Contracts guidelines where functions revert instead of
 * returning `false` on failure. 
 * 
 * @author Revoluzion Ecosystem
 * @custom:email support@revoluzion.io
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
 * @title ERC20 Token Standard Error Interface
 * 
 * @notice Interface of the ERC-6093 custom errors that defined common errors
 * related to the ERC-20 standard token functionalities.
 * 
 * @dev See https://eips.ethereum.org/EIPS/eip-6093
 */
interface IERC20Errors {
    
    // ERROR

    /**
     * @notice Error indicating that the `sender` has inssufficient `balance` for the operation.
     * 
     * @param sender Address whose tokens are being transferred.
     * @param balance Current balance for the interacting account.
     * @param needed Minimum amount required to perform a transfer.
     *
     * @dev The `needed` value is required to inform user on the needed amount.
     */
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);

    /**
     * @notice Error indicating that the `sender` is invalid for the operation.
     * 
     * @param sender Address whose tokens are being transferred.
     */
    error ERC20InvalidSender(address sender);
    
    /**
     * @notice Error indicating that the `receiver` is invalid for the operation.
     * 
     * @param receiver Address to which tokens are being transferred.
     */
    error ERC20InvalidReceiver(address receiver);
    
    /**
     * @notice Error indicating that the `spender` does not have enough `allowance` for the operation.
     * 
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     * @param allowance Amount of tokens a `spender` is allowed to operate with.
     * @param needed Minimum amount required to perform a transfer.
     * 
     * @dev The `needed` value is required to inform user on the needed amount.
     */
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    
    /**
     * @notice Error indicating that the `approver` is invalid for the approval operation.
     * 
     * @param approver Address initiating an approval operation.
     */
    error ERC20InvalidApprover(address approver);

    /**
     * @notice Error indicating that the `spender` is invalid for the allowance operation.
     * 
     * @param spender Address that may be allowed to operate on tokens without being their owner.
     */
    error ERC20InvalidSpender(address spender);
}

/**
 * @title Common Error Interface
 * 
 * @notice Interface of the common errors not specific to ERC-20 functionalities.
 */
interface ICommonErrors {

    // ERROR

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
  STAKING
********************************************************************************************/

/**
 * @title EternalAI Staking Contract
 * 
 * @notice Eternal AI Staking contract allows users to stake tokens, earn rewards, and manage
 * staking pools.
 * 
 * @dev This contract implements staking functionalities such as creating staking pools,
 * staking tokens, earning rewards, and managing the staking settings.
 */
contract EternalAIStaking is Auth, Pausable, ICommonErrors {

    // LIBRARY

    using SafeERC20 for IERC20;
    using Address for address;

    // DATA

    struct Leaderboard {
        uint256 amountStaked;
        uint256 totalStaking;
        uint256 activeStaking;
        uint256 inactiveStaking;
        address user;
    }

    struct TokenInfo {
        uint256 locked;
        uint256 claimed;
    }

    struct RewardInfo {
        address rewardToken;
        address stakeToken;
        address creator;
        uint256 totalStaker;
        uint256 createTime;
        uint256 stakeDuration;
        uint256 amountAdded;
        uint256 amountClaimed;
        uint256 amountAllocated;
        uint256 rewardsPerStake;
        uint256 rewardsPerStakeAccuracyFactor;
        bool status;
    }

    struct StakingInfo {
        uint256 amountStaked;
        uint256 totalStaking;
        uint256 activeStaking;
        uint256 inactiveStaking;
    }

    struct StakeInfo {
        bool stakeActive;
        address stakeToken;
        uint256 stakeTime;
        uint256 unstakeTime;
        uint256 totalEarned;
        uint256 stakeAmount;
        uint256 rewardAmount;
    }

    address public projectOwner;
    address public penaltyReceiver;
    address public currentStakeToken;
    address public currentRewardToken;

    uint256 public constant DENOMINATOR = 100_000;

    uint256 public penaltyPercentage = 20_000;
    uint256 public rewardsPerStakeAccuracyFactor = 0;
    uint256 public totalRewardPool = 0;
    uint256 public totalStaking = 0;
    uint256 public totalStaked = 0;

    bool public isFailsafeLocked = false;
    bool public emergencyWithdraw = false;
    bool public takePenalty = false;
    bool public wTokenLocked = false;

    // MAPPING

    mapping(address tokenAddress => bool) public isStakeToken;
    mapping(address rewardAddress => bool) public isRewardToken;
    mapping(address tokenAddress => TokenInfo) public infoStakeToken;
    mapping(address rewardAddress => TokenInfo) public infoRewardToken;
    mapping(uint256 poolId => RewardInfo) public rewardPool;
    mapping(uint256 poolId => bool) public poolClosed;
    mapping(uint256 poolId => uint256) public maxStakeAllowed;
    mapping(uint256 poolId => uint256) public currentStakeAmount;
    mapping(uint256 poolId => mapping(address account => uint256)) public poolStakerIndex;
    mapping(uint256 poolId => mapping(uint256 stakerId => address)) public poolStakerAtIndex;
    mapping(uint256 poolId => mapping(address account => StakingInfo)) public poolUserStakingInfo;
    mapping(uint256 poolId => mapping(address account => mapping(uint256 stakeId => StakeInfo))) public poolUserStakes;
    mapping(uint256 poolId => mapping(address account => mapping(address tokenAddress => uint256))) public poolUserStakeAmount;
    mapping(uint256 poolId => mapping(address account => mapping(address rewardAddress => uint256))) public poolUserRewardAmount;
    mapping(uint256 poolId => mapping(address account => mapping(uint256 stakeId => bool))) public poolUserClaimStatus;

    // ERROR

    /**
     * @notice Error indicating that the stake is invalid.
     * 
     * @dev Should throw if called when the stake was closed or paused.
     */
    error InactiveStake();

    /**
     * @notice Error indicating that the stucked fund can no longer be rescued.
     * 
     * @dev Should throw if called wTokens are already locked.
     */
    error CanNoLongerRescueFund();

    /**
     * @notice Error indicating that the project owner cannot initiate transfer of Ether.
     * 
     * @dev Should throw if called by `projectOwner` address.
     */
    error ProjectOwnerCannotInitiateTransferEther();

    /**
     * @notice Error indicating that the cannot initiate with all current address.
     * 
     * @dev Should throw if called with all current addresses.
     */
    error CannotUseAllCurrentAddress();

    /**
     * @notice Error indicating that lock is active for given state and cannot be modified.
     * 
     * @param lockType The name of the lock.
     */
    error Locked(string lockType);

    /**
     * @notice Error indicating that stake id provided is invalid.
     * 
     * @param poolId The pool id that the stake was created for.
     * @param stakeId The stake id that trigger the error.
     * @param minId The minimum value that's valid for stake id.
     * @param maxId The maximum value that's valud for stake id.
     */
    error InvalidStakeId(uint256 poolId, uint256 stakeId, uint256 minId, uint256 maxId);

    /**
     * @notice Error indicating that pool id provided is invalid.
     * 
     * @param poolId The pool id that trigger the error.
     * @param minId The minimum value that's valid for pool id.
     * @param maxId The maximum value that's valud for pool id.
     */
    error InvalidPoolId(uint256 poolId, uint256 minId, uint256 maxId);

    /**
     * @notice Error indicating that it is not the time to unstake.
     * 
     * @param current The current timestamp.
     * @param unstakeTime The timestamp for the unstake.
     */
    error NotTimeToUnstake(uint256 current, uint256 unstakeTime);

    /**
     * @notice Error indicating that the users has no staking for the given pool id.
     * 
     * @param poolId The pool id being checked for user staking availability.
     */
    error UserHasNoStaking(uint256 poolId);

    /**
     * @notice Error indicating that the given pool id is inactive.
     * 
     * @param poolId The pool id being checked for inactiveness.
     */
    error PoolNotActive(uint256 poolId);

    /**
     * @notice Error indicating the current status.
     * 
     * @param status The current status.
     */
    error Status(string status);

    /**
     * @notice Error indicating that the amount exceed max allowed stake amount for given pool id.
     * 
     * @param poolId The pool id that the user want to stake for.
     * @param current The current amount that the user want to stake.
     * @param max The max amount allowed that the user can stake.
     */
    error AmountExceedMaxStakeAllowedForPool(uint256 poolId, uint256 current, uint256 max);

    // MODIFIER

    /**
     * @notice Modifier that allows access only to the project owner or current
     * smart contract owner.
     *
     * @dev Should throw if called by any account other than the project owner or
     * smart contract owner.
     */
    modifier onlyOwnerFailsafe() {
        checkOwnerFailsafe();
        _;
    }
    
    // CONSTRUCTOR

    constructor(
        address stakeToken,
        address rewardToken,
        address penaltyReceiverAddress
    ) Auth (msg.sender) {
        if (penaltyReceiverAddress == address(0) || penaltyReceiverAddress == address(0xdead)) {
            revert InvalidAddress(penaltyReceiverAddress);
        }
        penaltyReceiver = penaltyReceiverAddress;
        projectOwner = msg.sender;

        currentStakeToken = stakeToken;
        currentRewardToken = rewardToken;

        uint8 stakeDecimals = IERC20Metadata(stakeToken).decimals();
        uint8 rewardDecimals = IERC20Metadata(rewardToken).decimals();
        rewardsPerStakeAccuracyFactor = (1 * 10**stakeDecimals) * (1 * 10**rewardDecimals);

        isStakeToken[stakeToken] = true;
        isRewardToken[rewardToken] = true;
    }

    // EVENT

    /**
     * @notice Emitted when a lock is applied.
     * 
     * @param lockType The type of lock applied.
     * @param caller The address of the caller who applied the lock.
     * @param timestamp The timestamp when the lock was applied.
     */
    event Lock(string lockType, address caller, uint256 timestamp);

    /**
     * @notice Emitted when the value is updated.
     * 
     * @param oldValue The old value before the update.
     * @param newValue The new value after the update.
     * @param caller The address of the caller who updated the value.
     * @param timestamp The timestamp when the update occurred.
     */
    event UpdateValue(string valueType, uint256 oldValue, uint256 newValue, address caller, uint256 timestamp);
    
    /**
     * @notice Emitted when the state is updated.
     * 
     * @param oldState The old state before the update.
     * @param newState The new state after the update.
     * @param caller The address of the caller who updated the state.
     * @param timestamp The timestamp when the update occurred.
     */
    event UpdateState(string stateType, bool oldState, bool newState, address caller, uint256 timestamp);

    /**
     * @notice Emitted when the address is updated.
     * 
     * @param oldAddress The old address before the update.
     * @param newAddress The new address after the update.
     * @param caller The address of the caller who updated the address.
     * @param timestamp The timestamp when the update occurred.
     */
    event UpdateAddress(string addressType, address oldAddress, address newAddress, address caller, uint256 timestamp);

    /**
     * @notice Emitted when the staking rule is updated.
     * 
     * @param oldStakeToken The old stake token address before the update.
     * @param newStakeToken The new stake token address after the update.
     * @param oldRewardToken The old reward token address before the update.
     * @param newRewardToken The new reward token address after the update.
     * @param caller The address of the caller who updated the address.
     * @param timestamp The timestamp when the update occurred.
     */
    event UpdateStakingRule(address oldStakeToken, address oldRewardToken, address newStakeToken, address newRewardToken, address caller, uint256 timestamp);

    /**
     * @notice Emitted when a user stake token.
     * 
     * @param poolId The pool id for the stake that user staked for.
     * @param stakeId The stake id of the current stake by the user.
     * @param amount The amount of token being staked by the user.
     * @param stakeToken The address of the stake token being staked by the user.
     * @param caller The address of the user who stake the token.
     * @param timestamp The timestamp when the user staked the token.
     */
    event Stake(uint256 poolId, uint256 stakeId, uint256 amount, address stakeToken, address caller, uint256 timestamp);

    /**
     * @notice Emitted when a user unstake token.
     * 
     * @param poolId The pool id for the unstake that user unstaked from.
     * @param stakeId The stake id of the stake being unstaked by the user.
     * @param amount The amount of token being unstaked by the user.
     * @param stakeToken The address of the stake token being unstaked by the user.
     * @param caller The address of the user who unstake the token.
     * @param timestamp The timestamp when the user unstaked the token.
     */
    event Unstake(uint256 poolId, uint256 stakeId, uint256 amount, address stakeToken, address caller, uint256 timestamp);

    /**
     * @notice Emitted when the reward is being ditributed to the user.
     * 
     * @param poolId The pool id for the reward being taken from.
     * @param stakeId The stake id of the stake that the reward being ditributed for.
     * @param amount The amount of token being distributed for the reward to the user.
     * @param rewardToken The address of the reward token being distributed to the user.
     * @param staker The address of the staker receiving the reward being distributed.
     * @param caller The address of the caller who initiated the reward distribution.
     * @param timestamp The timestamp when the reward being distributed.
     */
    event RewardDistribute(uint256 poolId, uint256 stakeId, uint256 amount, address rewardToken, address staker, address caller, uint256 timestamp);

    /**
     * @notice Emitted when the pool is being closed.
     * 
     * @param poolId The pool id that is being closed.
     * @param rewardToReturn The amount of reward to be returned to the pool creator.
     * @param caller The address of the caller who initiated the closure of the pool.
     * @param timestamp The timestamp when the pool closed.
     */
    event PoolClosed(uint256 poolId, uint256 rewardToReturn, address caller, uint256 timestamp);

    // FUNCTION

    /* General */
    
    /**
     * @notice Allows the contract to receive Ether.
     * 
     * @dev This is a required feature to have in order to allow the smart contract
     * to be able to receive ether.
     */
    receive() external payable {}

    /**
     * @notice Withdraws tokens or Ether from the contract to a specified address.
     * 
     * @param tokenAddress The address of the token to withdraw.
     * @param amount The amount of tokens or Ether to withdraw.
     * 
     * @dev You need to use address(0) as `tokenAddress` to withdraw Ether and
     * use 0 as `amount` to withdraw the whole available amount in the smart contract.
     * Anyone can trigger this function to send the fund to the `projectOwner`.
     * Only `projectOwner` address will not be able to trigger this function to
     * withdraw Ether from the smart contract by himself/herself.
     */
    function wTokens(address tokenAddress, uint256 amount) external {
        if (wTokenLocked) {
            revert CanNoLongerRescueFund();
        }
        uint256 toTransfer = amount;
        
        if (tokenAddress == address(0)) {
            if (amount == 0) {
                toTransfer = address(this).balance;
            }
            if (msg.sender == projectOwner) {
                revert ProjectOwnerCannotInitiateTransferEther();
            }
            payable(projectOwner).transfer(toTransfer);
        } else if (isStakeToken[tokenAddress]) {
            uint256 remaining = infoStakeToken[tokenAddress].locked - infoStakeToken[tokenAddress].claimed;
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            uint256 available = balance - remaining;
            if (available == 0 || amount > available) {
                revert IERC20Errors.ERC20InsufficientBalance(msg.sender, available, amount);
            }
            if (amount == 0) {
                toTransfer = available;
            }
            IERC20(tokenAddress).safeTransfer(projectOwner, toTransfer);
        } else if (isRewardToken[tokenAddress]) {
            uint256 remaining = infoRewardToken[tokenAddress].locked - infoRewardToken[tokenAddress].claimed;
            uint256 balance = IERC20(tokenAddress).balanceOf(address(this));
            uint256 available = balance - remaining;
            if (available == 0 || amount > available) {
                revert IERC20Errors.ERC20InsufficientBalance(msg.sender, available, amount);
            }
            if (amount == 0) {
                toTransfer = available;
            }
            IERC20(tokenAddress).safeTransfer(projectOwner, toTransfer);
        } else {
            if (amount == 0) {
                toTransfer = IERC20(tokenAddress).balanceOf(address(this));
            }
            IERC20(tokenAddress).safeTransfer(projectOwner, toTransfer);
        }
    }

    /* Check */
    
    /**
     * @notice Checks if the caller is the project owner and reverts if not.
     * 
     * @dev Should throw if the sender is not the current project owner.
     */
    function checkOwnerFailsafe() internal view {
        checkFailsafeLock();
        if (projectOwner != msg.sender && owner() != msg.sender) {
            revert OwnableUnauthorizedAccount(msg.sender);
        }
    }

    /**
     * @notice Checks if the failsafe is already locked.
     * 
     * @dev Should throw if the failsafe locked.
     */
    function checkFailsafeLock() internal view {
        if (isFailsafeLocked) {
            revert Locked("Failsafe");
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
            revert CannotUseCurrentAddress(newAddress);
        }
    }

    /**
     * @notice Checks if using valid pool id.
     * 
     * @dev Should throw if using invalid id.
     */
    function checkPoolId(uint256 poolId) internal view {
        if (poolId < 1 || poolId > totalRewardPool) {
            revert InvalidPoolId(poolId, 1, totalRewardPool);
        }
    }

    /**
     * @notice Checks if using valid stake id.
     * 
     * @dev Should throw if using invalid id.
     */
    function checkStakeId(uint256 poolId, uint256 stakeId, address staker) internal view {
        if (stakeId < 1 || stakeId > poolUserStakingInfo[poolId][staker].totalStaking) {
            revert InvalidStakeId(poolId, stakeId, 1, poolUserStakingInfo[poolId][msg.sender].totalStaking);
        }
    }

    /**
     * @notice Calculates the pending reward for a specific staking position of a staker in a specified
     * reward pool.
     * 
     * @param poolId The ID of the reward pool for which the pending reward is being calculated.
     * @param stakeId The ID of the staking position for which the pending reward is being calculated.
     * @param staker The address of the staker for whom the pending reward is being calculated.
     * 
     * @return The pending reward for the specified staking position of the specified staker in the
     * specified reward pool.
     * 
     * @dev This function calculates and returns the pending reward for the specified staking position
     * identified by the `stakeId` of the specified staker in the specified reward pool identified by
     * the `poolId`. It checks if the reward for the staking position has already been claimed. If the
     * reward has not been claimed, it calculates the pending reward based on the stake amount, rewards
     * per stake, and rewards per stake accuracy  factor of the reward pool, and returns the result. If
     * the reward has been claimed, it returns 0 as the pending reward.
     */
    function checkReward(uint256 poolId, uint256 stakeId, address staker) public view returns (uint256) {
        uint256 amount = poolUserStakes[poolId][staker][stakeId].stakeAmount;
        uint256 reward = 0;
        if (!poolUserClaimStatus[poolId][staker][stakeId]) {
            reward = amount * rewardPool[stakeId].rewardsPerStake / rewardPool[stakeId].rewardsPerStakeAccuracyFactor;
        }
        return reward;
    }

    /**
     * @notice Retrieves the total pending rewards for a staker in a specified reward pool.
     * 
     * @param poolId The ID of the reward pool for which pending rewards are being retrieved.
     * @param staker The address of the staker for whom pending rewards are being retrieved.
     * 
     * @return The total pending rewards for the specified staker in the specified reward pool.
     * 
     * @dev This function calculates and returns the total pending rewards for a staker in the specified
     * reward pool identified by the `poolId`. It iterates through all the staking positions of the staker
     * within the pool and accumulates the pending rewards using the `checkReward` function. If the staker
     * has no staking positions or all staking positions are inactive, the function reverts with an error
     * message indicating that the user has no staking positions in the specified pool.
    */
    function getAllPendingReward(uint256 poolId, address staker) public view returns (uint256) {
        uint256 poolUserTotalStaking = poolUserStakingInfo[poolId][staker].totalStaking;
        uint256 pending = 0;
        if (poolUserTotalStaking < 1 || poolUserStakingInfo[poolId][staker].activeStaking < 1) {
            revert UserHasNoStaking(poolId);
        }
        for (uint256 i = 1; i <= poolUserTotalStaking; i++) {
            pending += checkReward(poolId, i, staker);
        }
        return pending;
    }

    /**
     * @notice Retrieves the pending rewards for a specific staking position of a staker in a specified
     * reward pool.
     * 
     * @param poolId The ID of the reward pool for which pending rewards are being retrieved.
     * @param stakeId The ID of the staking position for which pending rewards are being retrieved.
     * @param staker The address of the staker for whom pending rewards are being retrieved.
     * 
     * @return The pending rewards for the specified staking position of the specified staker in the
     * specified reward pool.
     * 
     * @dev This function calculates and returns the pending rewards for the specified staking position
     * identified by the `stakeId` of the specified staker in the specified reward pool identified by the
     * `poolId`. It checks if the staking position is active using the `checkStakeId` function. If the
     * staking position is inactive, the function reverts with an error message indicating that the stake
     * is inactive. Otherwise, it calculates the pending reward using the `checkReward` function and returns
     * the result.
     */
    function getPendingReward(uint256 poolId, uint256 stakeId, address staker) public view returns (uint256) {
        checkStakeId(poolId, stakeId, staker);
        if (!poolUserStakes[poolId][staker][stakeId].stakeActive) {
            revert InactiveStake();
        }
        return checkReward(poolId, stakeId, staker);
    }

    /**
     * @notice Retrieves the leaderboard for the specified pool.
     * 
     * @param poolId The ID of the pool for which the leaderboard is being retrieved.
     * 
     * @return An array of Leaderboard structs containing staking information for the pool.
     * 
     * @dev This function is publicly accessible and returns an array of Leaderboard structs
     * representing staking information.
     */
    function getLeaderboard(uint256 poolId) external view returns (Leaderboard[] memory) {
        Leaderboard[] memory board = new Leaderboard[](rewardPool[poolId].totalStaker);
        for (uint256 i = 0; i < rewardPool[poolId].totalStaker; i++) {
            address user = poolStakerAtIndex[poolId][i + 1];
            
            Leaderboard memory item = Leaderboard({
                amountStaked: poolUserStakingInfo[poolId][user].amountStaked,
                totalStaking: poolUserStakingInfo[poolId][user].totalStaking,
                activeStaking: poolUserStakingInfo[poolId][user].activeStaking,
                inactiveStaking: poolUserStakingInfo[poolId][user].inactiveStaking,
                user: user
            });
            board[i]= item;
        }

        for (uint256 i = 0; i < board.length - 1; i++) {
            for (uint256 j = 0; j < board.length - i - 1; j++) {
                if (board[j].amountStaked <= board[j + 1].amountStaked) {
                    Leaderboard memory temp = board[j];
                    board[j] = board[j + 1];
                    board[j + 1] = temp;
                }
            }
        }
        return board;
    }

    /* Update */

    /**
     * @notice Locks the failsafe feature, preventing access control once locked.
     * 
     * @dev This function will emits the Lock event.
     */
    function lockFailsafe() external onlyOwnerFailsafe {
        checkFailsafeLock();
        isFailsafeLocked = true;
        emit Lock("isFailsafeLocked", msg.sender, block.timestamp);
    }

    /**
     * @notice Locks the wToken feature, preventing stucked fund from being rescued.
     * 
     * @dev This function will emits the Lock event.
     */
    function lockWToken() external onlyOwner {
        if (wTokenLocked) {
            revert CanNoLongerRescueFund();
        }
        wTokenLocked = true;
        emit Lock("wToken", msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the penalty receiver address.
     * 
     * @param newReceiver The new address to set as the penalty receiver.
     * 
     * @dev This function can only be called by the owner of the contract and when in failsafe mode.
     * It checks if the new receiver address is valid by calling the `checkCurrentAddress` function.
     * It also checks if the new receiver address is not the zero address or the `0xdead` address.
     * If any of these checks fail, the function reverts with an error message. Otherwise, it updates
     * the penalty receiver address and emits an `UpdateAddress` event.
     */
    function updatePenaltyReceiver(address newReceiver) external onlyOwnerFailsafe {
        checkCurrentAddress(newReceiver, penaltyReceiver);
        checkInvalidAddress(newReceiver, address(0));
        checkInvalidAddress(newReceiver, address(0xdead));
        address oldReceiver = penaltyReceiver;
        penaltyReceiver = newReceiver;
        emit UpdateAddress("penaltyReceiver", oldReceiver, newReceiver, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the penalty percentage.
     * 
     * @param newPenalty The new penalty percentage to be set.
     * 
     * @dev This function can only be called by the owner of the contract and when in failsafe mode.
     * It checks if the new penalty percentage is valid by calling the `checkCurrentValue` function.
     * If the penalty percentage exceeds 20%, the function reverts with an error message. Otherwise,
     * it updates the penalty percentage and emits an `UpdateValue` event.
     */
    function updatePenalty(uint256 newPenalty) external onlyOwnerFailsafe {
        checkCurrentValue(newPenalty, penaltyPercentage);
        if (penaltyPercentage > 2_000) {
            revert InvalidValue(newPenalty);
        }
        uint256 oldPenalty = penaltyPercentage;
        penaltyPercentage = newPenalty;
        emit UpdateValue("penaltyPercentage", oldPenalty, newPenalty, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the take penalty state.
     * 
     * @param newState The new take penalty state to be set.
     * 
     * @dev This function can only be called by the owner of the contract and when in failsafe mode.
     * It updates the take penalty state to the specified new state. If the new state is the same as
     * the current state, the function reverts with an error message. Otherwise, it updates the take
     * penalty state and emits an `UpdateState` event.
     */
    function updateTakePenalty(bool newState) external onlyOwnerFailsafe {
        checkCurrentState(newState, takePenalty);
        bool oldState = takePenalty;
        takePenalty = newState;
        emit UpdateState("takePenalty", oldState, newState, msg.sender, block.timestamp);
    }

    /**
     * @notice Updates the emergency withdrawal state.
     * 
     * @param newState The new emergency withdrawal state to be set.
     * 
     * @dev This function can only be called by the owner of the contract and when in failsafe mode.
     * It updates the emergency withdrawal state to the specified new state. If the new state is the
     * same as the current state, the function reverts with an error message. Otherwise, it updates
     * the emergency withdrawal state and emits an `UpdateState` event.
     */
    function updateEmergencyWithdraw(bool newState) external onlyOwnerFailsafe {
        checkCurrentState(newState, emergencyWithdraw);
        bool oldState = emergencyWithdraw;
        emergencyWithdraw = newState;
        emit UpdateState("emergencyWithdraw", oldState, newState, msg.sender, block.timestamp);
    }

    /*
     * @notice Updates the staking rule by changing the stake token and reward token addresses.
     * 
     * @param newStakeToken The address of the new stake token.
     * @param newRewardToken The address of the new reward token.
     * 
     * @dev This function can only be called by the owner of the contract. It updates the staking
     * rule by changing the stake token and reward token addresses. If the new stake token and reward
     * token addresses are the same as the current ones, the function reverts with an error message.
     * This function will emits the UpdateStakingRule event.
     */
    function updateStakingRule(address newStakeToken, address newRewardToken) external onlyOwner {
        if (newStakeToken == currentStakeToken && newRewardToken == currentRewardToken) {
            revert CannotUseAllCurrentAddress();
        }
        address oldStakeToken = currentStakeToken;
        address oldRewardToken = currentRewardToken;
        currentStakeToken = newStakeToken;
        currentRewardToken = newRewardToken;

        uint8 stakeDecimals = IERC20Metadata(newStakeToken).decimals();
        uint8 rewardDecimals = IERC20Metadata(newRewardToken).decimals();
        rewardsPerStakeAccuracyFactor = (1 * 10**stakeDecimals) * (1 * 10**rewardDecimals);

        if (!isStakeToken[newStakeToken]) {
            isStakeToken[newStakeToken] = true;
        }
        if (!isRewardToken[newRewardToken]) {
            isRewardToken[newRewardToken] = true;
        }

        emit UpdateStakingRule(oldStakeToken, oldRewardToken, newStakeToken, newRewardToken, msg.sender, block.timestamp);
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
     * @notice Function to pause the contract.
     * 
     * @dev This function is accessible externally when not paused only by authorized account.
     */
    function pause() public override whenNotPaused authorized {
        super.pause();
    }

    /**
     * @notice Function to unpause the contract.
     * 
     * @dev This function is accessible externally when paused only by authorized account.
     */
    function unpause() public override whenPaused authorized {
        super.unpause();
    }

    /* Reward */
    
    /**
     * @notice Creates a new reward pool.
     * 
     * @param stakeDuration The duration for which stakes are locked in the reward pool.
     * @param rewardToAdd The amount of reward tokens to add to the reward pool.
     * @param maxTokenStake The maximum amount of tokens allowed to be staked in the pool.
     * 
     * @dev This function allows an authorized account to create a new reward pool. If multiple
     * reward pools are created sequentially, the previous pool is closed automatically to
     * prevent overlapping pools. This function will transfer the reward tokens from the caller
     * to the contract, hence it is important to first approve an allowance for this contract.
     */
    function createRewardPool(uint256 stakeDuration, uint256 rewardToAdd, uint256 maxTokenStake) external whenNotPaused authorized {
        uint256 allowance = IERC20(currentRewardToken).allowance(msg.sender, address(this));
        uint256 balance = IERC20(currentRewardToken).balanceOf(msg.sender);
        
        if (rewardToAdd < 1) {
            revert InvalidValue(rewardToAdd);
        }
        if (maxTokenStake < 1) {
            revert InvalidValue(maxTokenStake);
        }
        if (allowance < rewardToAdd) {
            revert IERC20Errors.ERC20InsufficientAllowance(address(this), allowance, rewardToAdd);
        }
        if (balance < rewardToAdd) {
            revert IERC20Errors.ERC20InsufficientBalance(msg.sender, balance, rewardToAdd);
        }

        totalRewardPool += 1;
        infoRewardToken[currentRewardToken].locked += rewardToAdd;
        rewardPool[totalRewardPool].stakeToken = currentStakeToken;
        rewardPool[totalRewardPool].rewardToken = currentRewardToken;
        rewardPool[totalRewardPool].creator = msg.sender;
        rewardPool[totalRewardPool].createTime = block.timestamp;
        rewardPool[totalRewardPool].stakeDuration = stakeDuration;
        rewardPool[totalRewardPool].amountAdded += rewardToAdd;
        rewardPool[totalRewardPool].rewardsPerStake = rewardsPerStakeAccuracyFactor * rewardToAdd / maxTokenStake;
        rewardPool[totalRewardPool].rewardsPerStakeAccuracyFactor = rewardsPerStakeAccuracyFactor;
        rewardPool[totalRewardPool].status = true;
        maxStakeAllowed[totalRewardPool] = maxTokenStake;
        if (totalRewardPool > 1 && !poolClosed[totalRewardPool - 1]) {
            poolClosed[totalRewardPool - 1] = true;
            closePool(totalRewardPool - 1);
        }
        IERC20(currentRewardToken).transferFrom(msg.sender, address(this), rewardToAdd);
    }

    /**
     * @notice Pauses the currently active reward pool.
     * 
     * @dev This function is externally accessible and can only be called by an authorized
     * address when the contract is not paused.
     */
    function pauseRewardPool() external whenNotPaused authorized {
        if (!rewardPool[totalRewardPool].status && !poolClosed[totalRewardPool]) {
            revert Status("Already Paused");
        }
        rewardPool[totalRewardPool].status = false;
        emit UpdateState("rewardPoolStatus", true, false, msg.sender, block.timestamp);
    }

    /**
     * @notice Unpauses the currently paused reward pool, allowing it to resume operation.
     * 
     * @dev This function is externally accessible and can only be called by an authorized
     * address when the contract is not paused.
     */
    function unpauseRewardPool() external whenNotPaused authorized {
        if (rewardPool[totalRewardPool].status && !poolClosed[totalRewardPool]) {
            revert Status("Already Running");
        }
        rewardPool[totalRewardPool].status = true;
        emit UpdateState("rewardPoolStatus", false, true, msg.sender, block.timestamp);
    }

    /**
     * @notice Closes the currently active reward pool, preventing further staking and rewards distribution.
     * 
     * @dev This function is externally accessible and can only be called by an authorized address when the
     * contract is not paused. Once closed, the pool's status is updated and additional actions may be
     * triggered internally.
     */
    function closeRewardPool() external whenNotPaused authorized {
        if (poolClosed[totalRewardPool]) {
            revert Status("Already Closed");
        }
        poolClosed[totalRewardPool] = true;
        closePool(totalRewardPool);
    }

    /**
     * @notice Closes the specified reward pool, finalizing its operation and returning any 
     * unallocated rewards to the creator.
     * 
     * @param poolId The ID of the reward pool to be closed.
     * 
     * @dev This function is internally used and should not be called directly from external
     * contracts or accounts.
     */
    function closePool(uint256 poolId) internal {
        if (rewardPool[poolId].status) {
            rewardPool[poolId].status = false;
        }

        uint256 balance = IERC20(rewardPool[poolId].rewardToken).balanceOf(msg.sender);
        uint256 rewardToReturn = rewardPool[poolId].amountAdded - rewardPool[poolId].amountAllocated;

        infoRewardToken[rewardPool[poolId].rewardToken].claimed += rewardToReturn;
        uint256 available = infoRewardToken[rewardPool[poolId].rewardToken].locked - infoRewardToken[rewardPool[poolId].rewardToken].claimed;
        if (available < rewardToReturn) {
            revert IERC20Errors.ERC20InsufficientBalance(msg.sender, balance, rewardToReturn);
        }
        emit PoolClosed(poolId, rewardToReturn, msg.sender, block.timestamp);
        IERC20(rewardPool[poolId].rewardToken).transfer(rewardPool[poolId].creator, rewardToReturn);
    }

    /* Staking */
    
    /**
     * @notice Allows a user to stake tokens into a specific pool.
     * 
     * @param poolId The ID of the pool in which the tokens will be staked.
     * @param amount The amount of tokens to be staked.
     * 
     * @dev This function can only be called when the contract is not paused.
     * It checks various conditions including the validity of the pool ID, the amount of tokens being staked,
     * the allowance of tokens to be spent by the contract, and the balance of tokens in the user's account.
     * If any of these conditions fail, the function reverts with an appropriate error message.
     * Otherwise, it updates the staking information for the user and the pool, calculates rewards,
     * transfers the staked tokens to the contract, and emits a `Stake` event.
     */
    function stake(uint256 poolId, uint256 amount) external whenNotPaused {
        uint256 allowance = IERC20(rewardPool[poolId].stakeToken).allowance(msg.sender, address(this));
        uint256 balance = IERC20(rewardPool[poolId].stakeToken).balanceOf(msg.sender);
        uint256 allowed = maxStakeAllowed[poolId] - currentStakeAmount[poolId];
        
        checkPoolId(poolId);
        
        if (amount < 1) {
            revert InvalidValue(amount);
        }
        if (allowance < amount) {
            revert IERC20Errors.ERC20InsufficientAllowance(address(this), allowance, amount);
        }
        if (balance < amount) {
            revert IERC20Errors.ERC20InsufficientBalance(msg.sender, balance, amount);
        }
        if (!rewardPool[poolId].status || poolClosed[poolId]) {
            revert PoolNotActive(poolId);
        }
        if (allowed < amount) {
            revert AmountExceedMaxStakeAllowedForPool(poolId, amount, allowed);
        }

        if (poolUserStakingInfo[poolId][msg.sender].amountStaked == 0) {
            addStaker(poolId, msg.sender);
        }
        
        poolUserStakingInfo[poolId][msg.sender].totalStaking += 1;
        poolUserStakingInfo[poolId][msg.sender].activeStaking += 1;
        poolUserStakingInfo[poolId][msg.sender].amountStaked += amount;

        uint256 reward = amount * rewardPool[poolId].rewardsPerStake / rewardPool[poolId].rewardsPerStakeAccuracyFactor;
        rewardPool[poolId].amountAllocated += reward;
        
        poolUserStakes[poolId][msg.sender][poolUserStakingInfo[poolId][msg.sender].totalStaking].stakeActive = true;
        poolUserStakes[poolId][msg.sender][poolUserStakingInfo[poolId][msg.sender].totalStaking].stakeTime = block.timestamp;
        poolUserStakes[poolId][msg.sender][poolUserStakingInfo[poolId][msg.sender].totalStaking].unstakeTime = block.timestamp + rewardPool[poolId].stakeDuration;
        poolUserStakes[poolId][msg.sender][poolUserStakingInfo[poolId][msg.sender].totalStaking].stakeAmount = amount;
        poolUserStakes[poolId][msg.sender][poolUserStakingInfo[poolId][msg.sender].totalStaking].stakeToken = rewardPool[poolId].stakeToken;
        poolUserStakes[poolId][msg.sender][poolUserStakingInfo[poolId][msg.sender].totalStaking].rewardAmount = reward;
        
        currentStakeAmount[poolId] += amount;

        poolUserStakeAmount[poolId][msg.sender][rewardPool[poolId].stakeToken] += amount;

        infoStakeToken[rewardPool[poolId].stakeToken].locked += amount;
    
        totalStaking += 1;
        totalStaked += amount;
        
        IERC20(rewardPool[poolId].stakeToken).transferFrom(msg.sender, address(this), amount);

        emit Stake(poolId, poolUserStakingInfo[poolId][msg.sender].totalStaking, amount, rewardPool[poolId].stakeToken, msg.sender, block.timestamp);
    }

    /**
     * @notice Unstakes tokens from a specified pool and stake ID.
     * 
     * @param poolId The ID of the reward pool from which tokens are being unstaked.
     * @param stakeId The ID of the stake from which tokens are being unstaked.
     * 
     * @dev This function allows users to unstake tokens from a specified pool and stake ID.
     * If the unstake time has not yet been reached and emergency withdrawal is not enabled, the
     * function reverts with an appropriate error message. Otherwise, it distributes any accrued
     * rewards, updates the user's staking information, decrements the total staking count, and
     * transfers the unstaked amount of tokens back to the user. If emergency withdrawal and
     * penalty are enabled, it calculates and transfers the penalty amount to the penalty receiver
     * before transferring the remaining unstaked tokens to the user. Finally, it emits an Unstake
     * event to notify external observers of the unstaking action.
     */
    function unstake(uint256 poolId, uint256 stakeId) external {
        uint256 amount = poolUserStakes[poolId][msg.sender][stakeId].stakeAmount;
        
        checkStakeId(poolId, stakeId, msg.sender);
        checkPoolId(poolId);
        if (!poolUserStakes[poolId][msg.sender][stakeId].stakeActive) {
            revert InactiveStake();
        }
        if (
            amount < 1 ||
            amount > poolUserStakingInfo[poolId][msg.sender].amountStaked ||
            amount > poolUserStakes[poolId][msg.sender][stakeId].stakeAmount
        ) {
            revert InvalidValue(amount);
        }
        if (
            block.timestamp < poolUserStakes[poolId][msg.sender][stakeId].unstakeTime &&
            !emergencyWithdraw
        ) {
            revert NotTimeToUnstake(block.timestamp, poolUserStakes[poolId][msg.sender][stakeId].unstakeTime);
        }

        distributeReward(poolId, stakeId, msg.sender);

        poolUserStakingInfo[poolId][msg.sender].amountStaked -= amount;
        poolUserStakes[poolId][msg.sender][stakeId].stakeAmount -= amount;
        if (poolUserStakes[poolId][msg.sender][stakeId].stakeAmount < 1) {
            poolUserStakingInfo[poolId][msg.sender].inactiveStaking += 1;
            poolUserStakingInfo[poolId][msg.sender].activeStaking -= 1;
            poolUserStakes[poolId][msg.sender][stakeId].stakeActive = false;
            totalStaking -= 1;
        }

        address stakeTokenAddress = poolUserStakes[poolId][msg.sender][stakeId].stakeToken;
        poolUserStakeAmount[poolId][msg.sender][stakeTokenAddress] -= amount;
        infoStakeToken[stakeTokenAddress].claimed += amount;
        totalStaked -= amount;

        if (poolUserStakingInfo[poolId][msg.sender].activeStaking < 1) {
            removeStaker(poolId, msg.sender);
        }

        uint256 newAmount = amount;
        if (
            block.timestamp < poolUserStakes[poolId][msg.sender][stakeId].unstakeTime &&
            emergencyWithdraw && 
            takePenalty
        ) {
            uint256 penaltyAmount = newAmount * penaltyPercentage / DENOMINATOR;
            IERC20(stakeTokenAddress).transfer(penaltyReceiver, penaltyAmount);
            newAmount -= penaltyAmount;
        }
        IERC20(stakeTokenAddress).transfer(msg.sender, newAmount);
        emit Unstake(poolId, stakeId, amount, currentStakeToken, msg.sender, block.timestamp);
    }

    /**
     * @notice Distributes rewards to a staker.
     * 
     * @param poolId The ID of the reward pool.
     * @param stakeId The ID of the stake within the reward pool.
     * @param staker The address of the staker to whom rewards are distributed.
     * 
     * @dev This internal function distributes rewards to the specified staker for a particular stake
     * in a reward pool. Rewards are distributed only if the staker has not yet claimed rewards for
     * the stake, and the current timestamp exceeds the unstake time for the stake. Once rewards are
     * distributed, the reward amount is added to the staker's total earned rewards, and the claim
     * status for the stake is updated. If it is trigger during emergency withdraw, the tracker for
     * reward token will be reset. The function transfers the reward tokens from the reward pool
     * to the staker and emits a `RewardDistribute` event to signal the distribution of rewards.
     */
    function distributeReward(uint256 poolId, uint256 stakeId, address staker) internal {
        uint256 amount = poolUserStakes[poolId][staker][stakeId].stakeAmount;
        address rewardTokenAddress = rewardPool[poolId].rewardToken;
        uint256 reward = amount * rewardPool[poolId].rewardsPerStake / rewardPool[poolId].rewardsPerStakeAccuracyFactor;
        if (
            !poolUserClaimStatus[poolId][staker][stakeId] &&
            block.timestamp > poolUserStakes[poolId][staker][stakeId].unstakeTime
        ) {
            rewardPool[poolId].amountClaimed += reward;
            infoRewardToken[rewardTokenAddress].claimed += reward;
            poolUserStakes[poolId][staker][stakeId].totalEarned += reward;
            poolUserRewardAmount[poolId][staker][rewardTokenAddress] += reward;
            poolUserClaimStatus[poolId][staker][stakeId] = true;
            IERC20(rewardTokenAddress).transfer(staker, reward);
            emit RewardDistribute(poolId, stakeId, reward, rewardTokenAddress, staker, msg.sender, block.timestamp);
        }
        if (
            !poolUserClaimStatus[poolId][staker][stakeId] &&
            block.timestamp <= poolUserStakes[poolId][msg.sender][stakeId].unstakeTime &&
            emergencyWithdraw
        ) {
            rewardPool[poolId].amountAllocated -= reward;
            poolUserClaimStatus[poolId][staker][stakeId] = true;
            poolUserStakes[poolId][msg.sender][poolUserStakingInfo[poolId][msg.sender].totalStaking].rewardAmount = 0;
        }

    }

    /* Stakers */

    /*
     * @notice Adds a staker to the specified pool.
     * 
     * @param poolId The ID of the pool to which the staker is being added.
     * @param staker The address of the staker being added.
     * 
     * @dev This function is internal and should only be called within the contract.
     */
    function addStaker(uint256 poolId, address staker) internal {
        rewardPool[poolId].totalStaker += 1;
        poolStakerIndex[poolId][staker] = rewardPool[poolId].totalStaker;
        poolStakerAtIndex[poolId][rewardPool[poolId].totalStaker] = staker;
    }

    /**
     * @notice Removes a staker from the specified pool.
     * 
     * @param poolId The ID of the pool from which the staker is being removed.
     * @param staker The address of the staker being removed.
     * 
     * @dev This function is internal and should only be called within the contract.
    */
    function removeStaker(uint256 poolId, address staker) internal {
        uint256 currentIndex = poolStakerIndex[poolId][staker];
        address lastStaker = poolStakerAtIndex[poolId][rewardPool[poolId].totalStaker];
        
        poolStakerIndex[poolId][lastStaker] = currentIndex;
        poolStakerAtIndex[poolId][currentIndex] = lastStaker;
        poolStakerIndex[poolId][staker] = 0;
        poolStakerAtIndex[poolId][rewardPool[poolId].totalStaker] = address(0);

        rewardPool[poolId].totalStaker -= 1;
    }
}