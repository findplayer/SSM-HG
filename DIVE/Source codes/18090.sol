//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Owner
 * @dev Set & change owner
 */
contract Ownable {

    address private owner;
    
    // event for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    
    // modifier to check if caller is owner
    modifier onlyOwner() {
        // If the first argument of 'require' evaluates to 'false', execution terminates and all
        // changes to the state and to Ether balances are reverted.
        // This used to consume all gas in old EVM versions, but not anymore.
        // It is often a good idea to use 'require' to check if functions are called correctly.
        // As a second argument, you can also provide an explanation about what went wrong.
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
    
    /**
     * @dev Set contract deployer as owner
     */
    constructor() {
        owner = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        emit OwnerSet(address(0), owner);
    }

    /**
     * @dev Change owner
     * @param newOwner address of new owner
     */
    function changeOwner(address newOwner) public onlyOwner {
        emit OwnerSet(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Return owner address 
     * @return address of owner
     */
    function getOwner() external view returns (address) {
        return owner;
    }
}


interface IUniswapV2Router01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
    external
    returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
    external
    payable
    returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IERC20 {

    function totalSupply() external view returns (uint256);
    
    function symbol() external view returns(string memory);
    
    function name() external view returns(string memory);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);
    
    /**
     * @dev Returns the number of decimal places
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

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
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeApprove: approve failed'
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeTransfer: transfer failed'
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::transferFrom: transferFrom failed'
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }
}

/**
 * @title IGovernable Interface
 * @notice This is an interface used by the AxelarGateway contract to manage governance and mint limiter roles.
 */
interface IGovernable {
    error NotGovernance();
    error NotMintLimiter();
    error InvalidGovernance();
    error InvalidMintLimiter();

    event GovernanceTransferred(address indexed previousGovernance, address indexed newGovernance);
    event MintLimiterTransferred(address indexed previousGovernance, address indexed newGovernance);

    /**
     * @notice Returns the governance address.
     * @return address of the governance
     */
    function governance() external view returns (address);

    /**
     * @notice Returns the mint limiter address.
     * @return address of the mint limiter
     */
    function mintLimiter() external view returns (address);

    /**
     * @notice Transfer the governance role to another address.
     * @param newGovernance The new governance address
     */
    function transferGovernance(address newGovernance) external;

    /**
     * @notice Transfer the mint limiter role to another address.
     * @param newGovernance The new mint limiter address
     */
    function transferMintLimiter(address newGovernance) external;
}

// General interface for upgradable contracts
interface IContractIdentifier {
    /**
     * @notice Returns the contract ID. It can be used as a check during upgrades.
     * @dev Meant to be overridden in derived contracts.
     * @return bytes32 The contract ID
     */
    function contractId() external pure returns (bytes32);
}


interface IImplementation is IContractIdentifier {
    error NotProxy();

    function setup(bytes calldata data) external;
}


/**
 * @title IOwnable Interface
 * @notice IOwnable is an interface that abstracts the implementation of a
 * contract with ownership control features. It's commonly used in upgradable
 * contracts and includes the functionality to get current owner, transfer
 * ownership, and propose and accept ownership.
 */
interface IOwnable {
    error NotOwner();
    error InvalidOwner();
    error InvalidOwnerAddress();

    event OwnershipTransferStarted(address indexed newOwner);
    event OwnershipTransferred(address indexed newOwner);

    /**
     * @notice Returns the current owner of the contract.
     * @return address The address of the current owner
     */
    function owner() external view returns (address);

    /**
     * @notice Returns the address of the pending owner of the contract.
     * @return address The address of the pending owner
     */
    function pendingOwner() external view returns (address);

    /**
     * @notice Transfers ownership of the contract to a new address
     * @param newOwner The address to transfer ownership to
     */
    function transferOwnership(address newOwner) external;

    /**
     * @notice Proposes to transfer the contract's ownership to a new address.
     * The new owner needs to accept the ownership explicitly.
     * @param newOwner The address to transfer ownership to
     */
    function proposeOwnership(address newOwner) external;

    /**
     * @notice Transfers ownership to the pending owner.
     * @dev Can only be called by the pending owner
     */
    function acceptOwnership() external;
}

// General interface for upgradable contracts
interface IUpgradable is IOwnable, IImplementation {
    error InvalidCodeHash();
    error InvalidImplementation();
    error SetupFailed();

    event Upgraded(address indexed newImplementation);

    function implementation() external view returns (address);

    function upgrade(
        address newImplementation,
        bytes32 newImplementationCodeHash,
        bytes calldata params
    ) external;
}

/**
 * @title IAxelarGasService Interface
 * @notice This is an interface for the AxelarGasService contract which manages gas payments
 * and refunds for cross-chain communication on the Axelar network.
 * @dev This interface inherits IUpgradable
 */
interface IAxelarGasService is IUpgradable {
    error NothingReceived();
    error InvalidAddress();
    error NotCollector();
    error InvalidAmounts();

    event GasPaidForContractCall(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event GasPaidForContractCallWithToken(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        string symbol,
        uint256 amount,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event NativeGasPaidForContractCall(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event NativeGasPaidForContractCallWithToken(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        string symbol,
        uint256 amount,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event GasPaidForExpressCall(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event GasPaidForExpressCallWithToken(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        string symbol,
        uint256 amount,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event NativeGasPaidForExpressCall(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event NativeGasPaidForExpressCallWithToken(
        address indexed sourceAddress,
        string destinationChain,
        string destinationAddress,
        bytes32 indexed payloadHash,
        string symbol,
        uint256 amount,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event GasAdded(
        bytes32 indexed txHash,
        uint256 indexed logIndex,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event NativeGasAdded(bytes32 indexed txHash, uint256 indexed logIndex, uint256 gasFeeAmount, address refundAddress);

    event ExpressGasAdded(
        bytes32 indexed txHash,
        uint256 indexed logIndex,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event NativeExpressGasAdded(
        bytes32 indexed txHash,
        uint256 indexed logIndex,
        uint256 gasFeeAmount,
        address refundAddress
    );

    event Refunded(
        bytes32 indexed txHash,
        uint256 indexed logIndex,
        address payable receiver,
        address token,
        uint256 amount
    );

    /**
     * @notice Pay for gas using ERC20 tokens for a contract call on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call
     * @param gasToken The address of the ERC20 token used to pay for gas
     * @param gasFeeAmount The amount of tokens to pay for gas
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    ) external;

    /**
     * @notice Pay for gas using ERC20 tokens for a contract call with tokens on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call with tokens will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call with tokens
     * @param symbol The symbol of the token to be sent with the call
     * @param amount The amount of tokens to be sent with the call
     * @param gasToken The address of the ERC20 token used to pay for gas
     * @param gasFeeAmount The amount of tokens to pay for gas
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payGasForContractCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    ) external;

    /**
     * @notice Pay for gas using native currency for a contract call on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;

    /**
     * @notice Pay for gas using native currency for a contract call with tokens on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call with tokens will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call with tokens
     * @param symbol The symbol of the token to be sent with the call
     * @param amount The amount of tokens to be sent with the call
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payNativeGasForContractCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount,
        address refundAddress
    ) external payable;

    /**
     * @notice Pay for gas using ERC20 tokens for an express contract call on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to express execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call
     * @param gasToken The address of the ERC20 token used to pay for gas
     * @param gasFeeAmount The amount of tokens to pay for gas
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payGasForExpressCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    ) external;

    /**
     * @notice Pay for gas using ERC20 tokens for an express contract call with tokens on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to express execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call with tokens will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call with tokens
     * @param symbol The symbol of the token to be sent with the call
     * @param amount The amount of tokens to be sent with the call
     * @param gasToken The address of the ERC20 token used to pay for gas
     * @param gasFeeAmount The amount of tokens to pay for gas
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payGasForExpressCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    ) external;

    /**
     * @notice Pay for gas using native currency for an express contract call on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to express execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payNativeGasForExpressCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable;

    /**
     * @notice Pay for gas using native currency for an express contract call with tokens on a destination chain.
     * @dev This function is called on the source chain before calling the gateway to express execute a remote contract.
     * @param sender The address making the payment
     * @param destinationChain The target chain where the contract call with tokens will be made
     * @param destinationAddress The target address on the destination chain
     * @param payload Data payload for the contract call with tokens
     * @param symbol The symbol of the token to be sent with the call
     * @param amount The amount of tokens to be sent with the call
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function payNativeGasForExpressCallWithToken(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount,
        address refundAddress
    ) external payable;

    /**
     * @notice Add additional gas payment using ERC20 tokens after initiating a cross-chain call.
     * @dev This function can be called on the source chain after calling the gateway to execute a remote contract.
     * @param txHash The transaction hash of the cross-chain call
     * @param logIndex The log index for the cross-chain call
     * @param gasToken The ERC20 token address used to add gas
     * @param gasFeeAmount The amount of tokens to add as gas
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function addGas(
        bytes32 txHash,
        uint256 logIndex,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    ) external;

    /**
     * @notice Add additional gas payment using native currency after initiating a cross-chain call.
     * @dev This function can be called on the source chain after calling the gateway to execute a remote contract.
     * @param txHash The transaction hash of the cross-chain call
     * @param logIndex The log index for the cross-chain call
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function addNativeGas(
        bytes32 txHash,
        uint256 logIndex,
        address refundAddress
    ) external payable;

    /**
     * @notice Add additional gas payment using ERC20 tokens after initiating an express cross-chain call.
     * @dev This function can be called on the source chain after calling the gateway to express execute a remote contract.
     * @param txHash The transaction hash of the cross-chain call
     * @param logIndex The log index for the cross-chain call
     * @param gasToken The ERC20 token address used to add gas
     * @param gasFeeAmount The amount of tokens to add as gas
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function addExpressGas(
        bytes32 txHash,
        uint256 logIndex,
        address gasToken,
        uint256 gasFeeAmount,
        address refundAddress
    ) external;

    /**
     * @notice Add additional gas payment using native currency after initiating an express cross-chain call.
     * @dev This function can be called on the source chain after calling the gateway to express execute a remote contract.
     * @param txHash The transaction hash of the cross-chain call
     * @param logIndex The log index for the cross-chain call
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function addNativeExpressGas(
        bytes32 txHash,
        uint256 logIndex,
        address refundAddress
    ) external payable;

    /**
     * @notice Allows the gasCollector to collect accumulated fees from the contract.
     * @dev Use address(0) as the token address for native currency.
     * @param receiver The address to receive the collected fees
     * @param tokens Array of token addresses to be collected
     * @param amounts Array of amounts to be collected for each respective token address
     */
    function collectFees(
        address payable receiver,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external;

    /**
     * @notice Refunds gas payment to the receiver in relation to a specific cross-chain transaction.
     * @dev Only callable by the gasCollector.
     * @dev Use address(0) as the token address to refund native currency.
     * @param txHash The transaction hash of the cross-chain call
     * @param logIndex The log index for the cross-chain call
     * @param receiver The address to receive the refund
     * @param token The token address to be refunded
     * @param amount The amount to refund
     */
    function refund(
        bytes32 txHash,
        uint256 logIndex,
        address payable receiver,
        address token,
        uint256 amount
    ) external;

    /**
     * @notice Returns the address of the designated gas collector.
     * @return address of the gas collector
     */
    function gasCollector() external returns (address);
}

interface IAxelarExecutable {
    error InvalidAddress();
    error NotApprovedByGateway();

    function gateway() external view returns (IAxelarGateway);

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external;

    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) external;
}

interface IAxelarGateway is IImplementation, IGovernable {
    /**********\
    |* Errors *|
    \**********/

    error NotSelf();
    error InvalidCodeHash();
    error SetupFailed();
    error InvalidAuthModule();
    error InvalidTokenDeployer();
    error InvalidAmount();
    error InvalidChainId();
    error InvalidCommands();
    error TokenDoesNotExist(string symbol);
    error TokenAlreadyExists(string symbol);
    error TokenDeployFailed(string symbol);
    error TokenContractDoesNotExist(address token);
    error BurnFailed(string symbol);
    error MintFailed(string symbol);
    error InvalidSetMintLimitsParams();
    error ExceedMintLimit(string symbol);

    /**********\
    |* Events *|
    \**********/

    event TokenSent(
        address indexed sender,
        string destinationChain,
        string destinationAddress,
        string symbol,
        uint256 amount
    );

    event ContractCall(
        address indexed sender,
        string destinationChain,
        string destinationContractAddress,
        bytes32 indexed payloadHash,
        bytes payload
    );

    event ContractCallWithToken(
        address indexed sender,
        string destinationChain,
        string destinationContractAddress,
        bytes32 indexed payloadHash,
        bytes payload,
        string symbol,
        uint256 amount
    );

    event Executed(bytes32 indexed commandId);

    event TokenDeployed(string symbol, address tokenAddresses);

    event ContractCallApproved(
        bytes32 indexed commandId,
        string sourceChain,
        string sourceAddress,
        address indexed contractAddress,
        bytes32 indexed payloadHash,
        bytes32 sourceTxHash,
        uint256 sourceEventIndex
    );

    event ContractCallApprovedWithMint(
        bytes32 indexed commandId,
        string sourceChain,
        string sourceAddress,
        address indexed contractAddress,
        bytes32 indexed payloadHash,
        string symbol,
        uint256 amount,
        bytes32 sourceTxHash,
        uint256 sourceEventIndex
    );

    event ContractCallExecuted(bytes32 indexed commandId);

    event TokenMintLimitUpdated(string symbol, uint256 limit);

    event OperatorshipTransferred(bytes newOperatorsData);

    event Upgraded(address indexed implementation);

    /********************\
    |* Public Functions *|
    \********************/

    function sendToken(
        string calldata destinationChain,
        string calldata destinationAddress,
        string calldata symbol,
        uint256 amount
    ) external;

    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external;

    function callContractWithToken(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount
    ) external;

    function isContractCallApproved(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        address contractAddress,
        bytes32 payloadHash
    ) external view returns (bool);

    function isContractCallAndMintApproved(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        address contractAddress,
        bytes32 payloadHash,
        string calldata symbol,
        uint256 amount
    ) external view returns (bool);

    function validateContractCall(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash
    ) external returns (bool);

    function validateContractCallAndMint(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes32 payloadHash,
        string calldata symbol,
        uint256 amount
    ) external returns (bool);

    /***********\
    |* Getters *|
    \***********/

    function authModule() external view returns (address);

    function tokenDeployer() external view returns (address);

    function tokenMintLimit(string memory symbol) external view returns (uint256);

    function tokenMintAmount(string memory symbol) external view returns (uint256);

    function allTokensFrozen() external view returns (bool);

    function implementation() external view returns (address);

    function tokenAddresses(string memory symbol) external view returns (address);

    function tokenFrozen(string memory symbol) external view returns (bool);

    function isCommandExecuted(bytes32 commandId) external view returns (bool);

    /************************\
    |* Governance Functions *|
    \************************/

    function setTokenMintLimits(string[] calldata symbols, uint256[] calldata limits) external;

    function upgrade(
        address newImplementation,
        bytes32 newImplementationCodeHash,
        bytes calldata setupParams
    ) external;

    /**********************\
    |* External Functions *|
    \**********************/

    function execute(bytes calldata input) external;
}

contract AxelarExecutable is IAxelarExecutable {
    IAxelarGateway public immutable gateway;

    constructor(address gateway_) {
        if (gateway_ == address(0)) revert InvalidAddress();

        gateway = IAxelarGateway(gateway_);
    }

    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) external {
        bytes32 payloadHash = keccak256(payload);

        if (!gateway.validateContractCall(commandId, sourceChain, sourceAddress, payloadHash))
            revert NotApprovedByGateway();

        _execute(sourceChain, sourceAddress, payload);
    }

    function executeWithToken(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) external {
        bytes32 payloadHash = keccak256(payload);

        if (
            !gateway.validateContractCallAndMint(
                commandId,
                sourceChain,
                sourceAddress,
                payloadHash,
                tokenSymbol,
                amount
            )
        ) revert NotApprovedByGateway();

        _executeWithToken(sourceChain, sourceAddress, payload, tokenSymbol, amount);
    }

    function _execute(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload
    ) internal virtual {}

    function _executeWithToken(
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata payload,
        string calldata tokenSymbol,
        uint256 amount
    ) internal virtual {}
}

contract RubberDuckyETHBuyer is Ownable, AxelarExecutable {

    /**
        Axelar Gas Service Contract
     */
    IAxelarGasService public immutable gasService;

    /**
        USDC token address, used in the bridge
     */
    address public USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /**
        V2 Router Contract
     */
    IUniswapV2Router02 public V2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    /** Path from WETH to middleware */
    address[] public path;

    /** Default Fee */
    uint256 public defaultFee = 200;

    /** Fee Denominator */
    uint256 private constant FEE_DENOM = 10_000;

    /** Fee Recipient */
    address public feeReceiver;

    /** Destination Chain */
    string public destinationChain = "Polygon";
    string public destinationAddress;

    /** Min Gas For Swap */
    uint256 public minGas;

    constructor(
        address gateway_, 
        address gasService_,
        address feeRecipient_
    ) AxelarExecutable(gateway_) {
        
        // set up Axelar Configs
        gasService = IAxelarGasService(gasService_);

        // set up contract configs
        path = new address[](2);
        path[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        path[1] = USDC;                                       // USDC
        feeReceiver = feeRecipient_;

        // set min gas
        minGas = 0.0005 ether;

        // Destination Address
        destinationAddress = string(abi.encodePacked(address(this)));
    }

    function setDestinationChain(string calldata destinationChain_) external onlyOwner {
        destinationChain = destinationChain_;
    }

    function setDestinationAddress(string calldata destinationAddress_) external onlyOwner {
        destinationAddress = destinationAddress_;
    }

    function setMinGas(uint256 minGas_) external onlyOwner {
        minGas = minGas_;
    }

    // set fee
    function setDefaultFee(uint256 fee_) external onlyOwner {
        require(fee_ <= FEE_DENOM/10, 'Invalid Fee');
        defaultFee = fee_;
    }

    // set USDC
    function setUSDC(address USDC_) external onlyOwner {
        require(USDC_ != address(0), 'Zero Address');
        USDC = USDC_;
    }

    // set v2 router
    function setV2Router(address v2Router_) external onlyOwner {
        require(v2Router_ != address(0), 'Zero Address');
        V2Router = IUniswapV2Router02(v2Router_);
    }

    // set path
    function setPath(address[] calldata path_) external onlyOwner {
        path = path_;
    }

    // set fee recipient
    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        require(feeRecipient_ != address(0), 'Zero Address');
        feeReceiver = feeRecipient_;
    }

    function withdraw(address token) external onlyOwner {
        TransferHelper.safeTransfer(token, msg.sender, IERC20(token).balanceOf(address(this)));
    }

    function withdrawETH() external onlyOwner {
        TransferHelper.safeTransferETH(msg.sender, address(this).balance);
    }

    receive() external payable {
        require(msg.value > minGas, 'Min Gas Error');
        _useBridge(msg.sender, minGas, 0, 0, 0);
    }

    function useBridge(address to, uint256 gas, uint256 minOutUSDC, uint256 minOut, uint112 percentForGas) external payable {
        require(
            gas >= minGas,
            'Min Gas Error'
        );
        require(
            msg.value > gas,
            'Too Much Gas'
        );
        require(
            to != address(0),
            'Zero To'
        );
        _useBridge(to, gas, minOutUSDC, minOut, percentForGas);
    }

    /**
        Used To Bridge Tokens To Destination Chains
     */
    function _useBridge(
        address to,
        uint256 gas,
        uint256 minOutUSDC,
        uint256 minOut,
        uint112 percentForGas
    ) internal {

        // amount to swap is value - gas
        uint256 preTaxAmount = msg.value - gas;

        // calculate fee
        uint256 feeAmount = ( preTaxAmount * defaultFee ) / FEE_DENOM;

        // amount to swap is preTaxAmount - fee
        uint256 amount = preTaxAmount - feeAmount;
        require(amount > 0, 'Zero Amount');

        // send fee to destination
        if (feeAmount > 0) {
            TransferHelper.safeTransferETH(feeReceiver, feeAmount);
        }

        // make swaps to get native into USDC
        uint256 usdcAmount = _swap(amount, minOutUSDC);

        // create payload using the amount received to cover tax-on-transfer tokens
        bytes memory payload = abi.encode(to, percentForGas, minOut);

        // pass payload into gasService, paying the gas for the next call
        gasService.payNativeGasForContractCallWithToken{value: gas} (
            address(this),
            destinationChain,
            destinationAddress,
            payload,
            "USDC",
            usdcAmount,
            msg.sender
        );

        // approve of USDC to the gateway
        TransferHelper.safeApprove(USDC, address(gateway), usdcAmount);

        // Call Contract On The Gateway
        gateway.callContractWithToken(
            destinationChain, 
            destinationAddress, 
            payload,
            "USDC",
            usdcAmount
        );
    }


    function _swap(uint256 amount, uint256 minOutUSDC) internal returns (uint256) {

        // swapping ETH to USDC
        V2Router.swapExactETHForTokens{value: amount}(
            minOutUSDC,
            path,
            address(this),
            block.timestamp + 1000
        );

        // return balance of USDC received
        return IERC20(USDC).balanceOf(address(this));
    }

    /**
     * @notice Add additional gas payment using native currency after initiating a cross-chain call.
     * @dev This function can be called on the source chain after calling the gateway to execute a remote contract.
     * @param txHash The transaction hash of the cross-chain call
     * @param logIndex The log index for the cross-chain call
     * @param refundAddress The address where refunds, if any, should be sent
     */
    function addNativeGas(
        bytes32 txHash,
        uint256 logIndex,
        address refundAddress
    ) external payable {
        gasService.addNativeGas{value: msg.value}(txHash, logIndex, refundAddress);
    }
}