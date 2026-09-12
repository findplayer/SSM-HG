// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

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
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
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
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// File: @chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol


pragma solidity ^0.8.0;

// End consumer library.
library Client {
  /// @dev RMN depends on this struct, if changing, please notify the RMN maintainers.
  struct EVMTokenAmount {
    address token; // token address on the local chain.
    uint256 amount; // Amount of tokens.
  }

  struct Any2EVMMessage {
    bytes32 messageId; // MessageId corresponding to ccipSend on source.
    uint64 sourceChainSelector; // Source chain selector.
    bytes sender; // abi.decode(sender) if coming from an EVM chain.
    bytes data; // payload sent in original message.
    EVMTokenAmount[] destTokenAmounts; // Tokens and their amounts in their destination chain representation.
  }

  // If extraArgs is empty bytes, the default is 200k gas limit.
  struct EVM2AnyMessage {
    bytes receiver; // abi.encode(receiver address) for dest EVM chains
    bytes data; // Data payload
    EVMTokenAmount[] tokenAmounts; // Token transfers
    address feeToken; // Address of feeToken. address(0) means you will send msg.value.
    bytes extraArgs; // Populate this with _argsToBytes(EVMExtraArgsV1)
  }

  // bytes4(keccak256("CCIP EVMExtraArgsV1"));
  bytes4 public constant EVM_EXTRA_ARGS_V1_TAG = 0x97a657c9;
  struct EVMExtraArgsV1 {
    uint256 gasLimit;
  }

  function _argsToBytes(EVMExtraArgsV1 memory extraArgs) internal pure returns (bytes memory bts) {
    return abi.encodeWithSelector(EVM_EXTRA_ARGS_V1_TAG, extraArgs);
  }
}

// File: @chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol


pragma solidity ^0.8.0;


interface IRouterClient {
  error UnsupportedDestinationChain(uint64 destChainSelector);
  error InsufficientFeeTokenAmount();
  error InvalidMsgValue();

  /// @notice Checks if the given chain ID is supported for sending/receiving.
  /// @param chainSelector The chain to check.
  /// @return supported is true if it is supported, false if not.
  function isChainSupported(uint64 chainSelector) external view returns (bool supported);

  /// @notice Gets a list of all supported tokens which can be sent or received
  /// to/from a given chain id.
  /// @param chainSelector The chainSelector.
  /// @return tokens The addresses of all tokens that are supported.
  function getSupportedTokens(uint64 chainSelector) external view returns (address[] memory tokens);

  /// @param destinationChainSelector The destination chainSelector
  /// @param message The cross-chain CCIP message including data and/or tokens
  /// @return fee returns execution fee for the message
  /// delivery to destination chain, denominated in the feeToken specified in the message.
  /// @dev Reverts with appropriate reason upon invalid message.
  function getFee(
    uint64 destinationChainSelector,
    Client.EVM2AnyMessage memory message
  ) external view returns (uint256 fee);

  /// @notice Request a message to be sent to the destination chain
  /// @param destinationChainSelector The destination chain ID
  /// @param message The cross-chain CCIP message including data and/or tokens
  /// @return messageId The message ID
  /// @dev Note if msg.value is larger than the required fee (from getFee) we accept
  /// the overpayment with no refund.
  /// @dev Reverts with appropriate reason upon invalid message.
  function ccipSend(
    uint64 destinationChainSelector,
    Client.EVM2AnyMessage calldata message
  ) external payable returns (bytes32);
}

// File: @chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol


pragma solidity ^0.8.0;

interface LinkTokenInterface {
  function allowance(address owner, address spender) external view returns (uint256 remaining);

  function approve(address spender, uint256 value) external returns (bool success);

  function balanceOf(address owner) external view returns (uint256 balance);

  function decimals() external view returns (uint8 decimalPlaces);

  function decreaseApproval(address spender, uint256 addedValue) external returns (bool success);

  function increaseApproval(address spender, uint256 subtractedValue) external;

  function name() external view returns (string memory tokenName);

  function symbol() external view returns (string memory tokenSymbol);

  function totalSupply() external view returns (uint256 totalTokensIssued);

  function transfer(address to, uint256 value) external returns (bool success);

  function transferAndCall(address to, uint256 value, bytes calldata data) external returns (bool success);

  function transferFrom(address from, address to, uint256 value) external returns (bool success);
}

// File: Bridge-ENO-Contracts/SenderETH.sol


pragma solidity 0.8.20;





contract SenderETH {
    enum PayFeesIn {
        Native,
        LINK
    }
    
    mapping(address => bool) private isOwner;
    bool public paused = false;

    address public i_router;
    address immutable i_link;

    uint256 public minEthRequired;
    IERC20 immutable tokenERC20;

    address public _unlocker;
    bool public unlockerSetEnabled = true;

    event MessageSent(bytes32 messageId);

    constructor(address router, address link, address _tokenERC20) {
        i_router = router;
        i_link = link;
        isOwner[msg.sender] = true;
        LinkTokenInterface(i_link).approve(i_router, type(uint256).max);
        tokenERC20 = IERC20(_tokenERC20);
    }

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Caller is not an owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier whenPaused() {
        require(paused, "Contract is not paused");
        _;
    }

    function addOwner(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        isOwner[newOwner] = true;
    }

    function pause() public onlyOwner whenNotPaused {
        paused = true;
    }

    function unpause() public onlyOwner whenPaused {
        paused = false;
    }

    function setRouter(address newRouter) public onlyOwner {
        require(newRouter != address(0), "Router cannot be the zero address");
        i_router = newRouter;
    }

    receive() external payable {}

    function setMinEthRequired(uint256 _minEth) external onlyOwner {
        minEthRequired = _minEth;
    }

    function mintWithMinEth(
        uint64 destinationChainSelector,
        address receiver,
        address finalRecipient,
        uint256 amount,
        PayFeesIn payFeesIn
    ) external payable whenNotPaused {
        require(msg.value >= minEthRequired, "Not enough ETH sent");
        require(tokenERC20.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        
        mintTokens(
            destinationChainSelector,
            receiver,
            finalRecipient,
            amount,
            payFeesIn
        );
    }

    function mintTokens(
        uint64 destinationChainSelector,
        address receiver,
        address finalRecipient,
        uint256 amount,
        PayFeesIn payFeesIn
    ) internal  {
        bytes memory data = abi.encodeWithSignature("mint(address,uint256)", finalRecipient, amount);

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver), 
            data: data, 
            tokenAmounts: new Client.EVMTokenAmount[](0), 
            extraArgs: "", 
            feeToken: payFeesIn == PayFeesIn.LINK ? i_link : address(0) 
        });

        uint256 fee = IRouterClient(i_router).getFee(
            destinationChainSelector,
            message
        );

        bytes32 messageId;

        if (payFeesIn == PayFeesIn.LINK) {
            messageId = IRouterClient(i_router).ccipSend(
                destinationChainSelector,
                message
            );
        } else {
            messageId = IRouterClient(i_router).ccipSend{value: fee}(
                destinationChainSelector,
                message
            );
        }

        emit MessageSent(messageId);
    }

    function withdrawEther() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance");

        payable(msg.sender).transfer(balance);
    }

    function unlock(address to, uint256 amount) public {
        require(msg.sender == _unlocker, "Caller is not the unlocker");
        require(tokenERC20.balanceOf(address(this)) >= amount, "Insufficient token balance in contract");

        tokenERC20.transfer(to, amount);
    }

    function setUnlocker(address unlocker) public onlyOwner {
        require(unlockerSetEnabled, "Setting unlocker is disabled");
        _unlocker = unlocker;
    }

    function disableSetUnlocker() public onlyOwner {
        unlockerSetEnabled = false;
    }

    function withdrawLinkTokens(address to, uint256 amount) public onlyOwner {
        require(to != address(0), "Cannot withdraw to the zero address");
        require(amount > 0, "Amount must be greater than 0");
        require(IERC20(i_link).balanceOf(address(this)) >= amount, "Insufficient LINK balance");

        bool sent = IERC20(i_link).transfer(to, amount);
        require(sent, "Token transfer failed");
    }
    
}