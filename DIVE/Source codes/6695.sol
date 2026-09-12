// SPDX-License-Identifier: MIT

// File @openzeppelin/contracts/utils/introspection/IERC165.sol@v4.8.1


// OpenZeppelin Contracts v4.4.1 (utils/introspection/IERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}


// File @openzeppelin/contracts/token/ERC1155/IERC1155.sol@v4.8.1


// OpenZeppelin Contracts (last updated v4.7.0) (token/ERC1155/IERC1155.sol)

pragma solidity ^0.8.0;

/**
 * @dev Required interface of an ERC1155 compliant contract, as defined in the
 * https://eips.ethereum.org/EIPS/eip-1155[EIP].
 *
 * _Available since v3.1._
 */
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(address[] calldata accounts, uint256[] calldata ids)
        external
        view
        returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}


// File @openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol@v4.8.1


// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC1155/IERC1155Receiver.sol)

pragma solidity ^0.8.0;

/**
 * @dev _Available since v3.1._
 */
interface IERC1155Receiver is IERC165 {
    /**
     * @dev Handles the receipt of a single ERC1155 token type. This function is
     * called at the end of a `safeTransferFrom` after the balance has been updated.
     *
     * NOTE: To accept the transfer, this must return
     * `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
     * (i.e. 0xf23a6e61, or its own function selector).
     *
     * @param operator The address which initiated the transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param id The ID of the token being transferred
     * @param value The amount of tokens being transferred
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4);

    /**
     * @dev Handles the receipt of a multiple ERC1155 token types. This function
     * is called at the end of a `safeBatchTransferFrom` after the balances have
     * been updated.
     *
     * NOTE: To accept the transfer(s), this must return
     * `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
     * (i.e. 0xbc197c81, or its own function selector).
     *
     * @param operator The address which initiated the batch transfer (i.e. msg.sender)
     * @param from The address which previously owned the token
     * @param ids An array containing ids of each token being transferred (order and length must match values array)
     * @param values An array containing amounts of each token being transferred (order and length must match ids array)
     * @param data Additional data with no specified format
     * @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4);
}


// File @openzeppelin/contracts/utils/introspection/ERC165.sol@v4.8.1


// OpenZeppelin Contracts v4.4.1 (utils/introspection/ERC165.sol)

pragma solidity ^0.8.0;

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}


// File @openzeppelin/contracts/token/ERC1155/utils/ERC1155Receiver.sol@v4.8.1


// OpenZeppelin Contracts v4.4.1 (token/ERC1155/utils/ERC1155Receiver.sol)

pragma solidity ^0.8.0;


/**
 * @dev _Available since v3.1._
 */
abstract contract ERC1155Receiver is ERC165, IERC1155Receiver {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(interfaceId);
    }
}


// File contracts/IEthrunes.sol


pragma solidity ^0.8.17;

interface IEthrunes is IERC1155 {

  function transfer(
    address to,
    uint256 id,
    uint256 amount,
    bytes memory data
  ) external payable;

  function batchTransfer(
    address to,
    uint256[] memory ids,
    uint256[] memory amounts,
    bytes memory data
  ) external payable;

  function deploy2(
    string calldata tick,
    uint8 decimals,
    uint256 supply,
    address to
  ) external payable;

  function tokens(uint160 _id) external view returns(
    uint160 id,
    uint8 decimals,
    uint256 supply,
    uint256 limit,
    string memory tick
  );

  function totalSupply(uint256 id) external view returns (uint256);
}


// File @openzeppelin/contracts/security/ReentrancyGuard.sol@v4.8.1


// OpenZeppelin Contracts (last updated v4.8.0) (security/ReentrancyGuard.sol)

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        // On the first call to nonReentrant, _status will be _NOT_ENTERED
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}


// File @openzeppelin/contracts/token/ERC20/IERC20.sol@v4.8.1


// OpenZeppelin Contracts (last updated v4.6.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

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


// File contracts/TransferHelper.sol


pragma solidity >=0.6.0;

library TransferHelper {
    /// @notice Transfers tokens from the targeted address to the given destination
    /// @notice Errors with 'STF' if transfer fails
    /// @param token The contract address of the token to be transferred
    /// @param from The originating address from which the tokens will be transferred
    /// @param to The destination address of the transfer
    /// @param value The amount to be transferred
    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
    }

    /// @notice Transfers tokens from msg.sender to a recipient
    /// @dev Errors with ST if transfer fails
    /// @param token The contract address of the token which will be transferred
    /// @param to The recipient of the transfer
    /// @param value The value of the transfer
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
    }

    /// @notice Approves the stipulated contract to spend the given allowance in the given token
    /// @dev Errors with 'SA' if transfer fails
    /// @param token The contract address of the token to be approved
    /// @param to The target of the approval
    /// @param value The amount of the given token the target will be allowed to spend
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.approve.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'SA');
    }

    /// @notice Transfers ETH to the recipient address
    /// @dev Fails with `STE`
    /// @param to The destination of the transfer
    /// @param value The value to be transferred
    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }
}


// File contracts/LaunchSwap.sol


pragma solidity ^0.8.17;




contract LaunchSwap is ReentrancyGuard, ERC1155Receiver {
  error InvalidSender();
  error InvalidCall();
  error NotSupportBatchReceivedCallback();
  error PoolAlreadyCreated();
  error ExceedLimitPerBuy();
  error ExceedLimitPerSell();
  error InsufficientAmountOut();
  error InsufficientAmountIn();
  error LessThanAmountOutMin();
  error Expired();
  error InitialPriceTooLow();
  error InvalidTotalSupply();
  error TotalSupplyMustBeEven();
  error ZeroAmountIn();
  error InvalidRecipient();
  error InvalidFeeRate();

  struct Pool {
    uint256 reserve0;
    uint256 reserve1;
    uint256 halfReserve;
    uint256 price;
    uint256 limitPerBuy;
    uint256 limitPerSell;
    uint256 fee;
    address creator;
    uint256 creatorFees;
  }

  uint256 public accProtocolFees;
  uint16 public protocolFee = 20; // 20% for creator and service
  address public ethrunes;
  address feeRecipient;
  address dev;

  mapping (uint160 => Pool) public pools;
  mapping (uint256 => bool) public feeTiers;
  

  event CreatePool(address indexed creator, uint160 indexed id, uint256 amount, uint256 price, uint256 fee);
  event Buy(uint160 indexed id, uint256 amountInEth, uint256 amountOut);
  event Sell(uint160 indexed id, uint256 amountIn, uint256 amountOutEth);

  constructor(address _ethrunes, address _feeRecipient) {
    ethrunes = _ethrunes;
    feeRecipient = _feeRecipient;
    dev = msg.sender;
    feeTiers[300] = true;
    feeTiers[200] = true;
    feeTiers[100] = true;
    feeTiers[50] = true;
    feeTiers[30] = true;
  }

  modifier checkDeadline(uint256 deadline) {
    if(deadline < block.timestamp) revert Expired();
    _;
  }

  function _createPool(
    uint160 id,
    uint256 amount,
    uint256 price,
    uint256 limitPerBuy,
    uint256 limitPerSell,
    uint256 fee,
    address creator
  ) internal {
    Pool storage pool = pools[id];
    if(pool.reserve1 != 0) revert PoolAlreadyCreated();
    uint256 supply = IEthrunes(ethrunes).totalSupply(id);
    if(amount != supply) revert InvalidTotalSupply();
    if(!feeTiers[fee]) revert InvalidFeeRate();
    if(amount / 2 * 2 != amount) revert TotalSupplyMustBeEven();

    pool.reserve0 = 0;
    pool.reserve1 = amount;
    pool.halfReserve = amount / 2;
    pool.price = price;
    pool.limitPerBuy = limitPerBuy;
    pool.limitPerSell = limitPerSell;
    pool.fee = fee;
    pool.creator = creator;

    if(pool.halfReserve * pool.price / 1e18 == 0) revert InitialPriceTooLow();

    emit CreatePool(creator, id, amount, price, fee);
  }


  function buy(
    uint160 id, 
    uint256 amountOut, 
    uint256 deadline,
    address recipient
  ) external payable checkDeadline(deadline) nonReentrant returns(uint256) {
    if(msg.value == 0) revert ZeroAmountIn();
    Pool storage pool = pools[id];
    if(pool.limitPerBuy > 0 && amountOut > pool.limitPerBuy) revert ExceedLimitPerBuy();
    if(amountOut >= pool.reserve1) revert InsufficientAmountOut();

    uint256 buyAmount;
    uint256 swapAmount;

    if(pool.reserve1 > pool.halfReserve) {
      uint256 maxBuyAmount = pool.reserve1 - pool.halfReserve;
      if(maxBuyAmount >= amountOut) {
        buyAmount = amountOut;
      } else {
        swapAmount = amountOut - maxBuyAmount;
        buyAmount = maxBuyAmount;
      }
    } else {
      swapAmount = amountOut;
    }

    uint256 amountIn;

    if(buyAmount > 0) {
      amountIn = pool.price * buyAmount / 1e18;
      pool.reserve0 += amountIn;
      pool.reserve1 -= buyAmount;
    }

    if(swapAmount > 0) {
      if(swapAmount >= pool.reserve1) revert InsufficientAmountOut();

      uint256 numerator =  swapAmount * pool.reserve0;
      uint256 denominator = pool.reserve1 - swapAmount;

      uint256 swapAmountIn = numerator / denominator + 1;

      uint256 feeAmount = swapAmountIn * pool.fee / 10000;

      uint256 _protocolFees = feeAmount * protocolFee / 100;
      uint256 _creatorFee = _protocolFees * 75 / 100;
      uint256 providerFees = feeAmount - _protocolFees;

      accProtocolFees += (_protocolFees - _creatorFee);

      pool.creatorFees += _creatorFee;
      pool.reserve0 += swapAmountIn;
      pool.reserve1 -= swapAmount;
      pool.price += (providerFees * 1e18 / pool.halfReserve);

      amountIn += (swapAmountIn + feeAmount);
    }

    if(msg.value < amountIn) revert InsufficientAmountIn();

    bytes memory data;
    if(recipient == address(0x0) || recipient == msg.sender) {
      recipient = msg.sender;
    } else {
      data = abi.encode(msg.sender);
    }
    IEthrunes(ethrunes).transfer(recipient, id, amountOut, data);

    uint256 refund = msg.value - amountIn;

    // refund
    if(refund > 0) {
      TransferHelper.safeTransferETH(msg.sender, refund);
    }

    emit Buy(id, amountIn, amountOut);

    return amountIn;
  }

  function _sell(
    uint160 id, 
    address to,
    uint256 amountIn, 
    uint256 amountOutMin, 
    uint256 deadline
  ) internal checkDeadline(deadline) nonReentrant {
    Pool storage pool = pools[id];
    if(to == address(0x0)) revert InvalidRecipient();
    if(amountIn == 0) revert ZeroAmountIn();

    if(pool.limitPerSell > 0 && amountIn > pool.limitPerSell) revert ExceedLimitPerSell();

    uint256 sellAmount;
    uint256 swapAmount;

    if(pool.reserve1 >= pool.halfReserve) {
      sellAmount = amountIn;
    } else {
      uint256 maxSwapAmount = pool.halfReserve - pool.reserve1;
      if(maxSwapAmount >= amountIn) {
        swapAmount = amountIn;
      } else {
        swapAmount = maxSwapAmount;
        sellAmount = amountIn - maxSwapAmount;
      }
    }

    uint256 amountOut;
    if(swapAmount > 0) {
      uint256 numerator =  swapAmount * pool.reserve0;
      uint256 denominator = pool.reserve1 + swapAmount;
      amountOut = numerator / denominator - 1;

      uint256 feeAmount = amountOut * pool.fee / 10000;

      uint256 _protocolFees = feeAmount * protocolFee / 100;
      uint256 _creatorFee = _protocolFees * 75 / 100;

      uint256 providerFees = feeAmount - _protocolFees;

      accProtocolFees += (_protocolFees - _creatorFee);

      pool.creatorFees += _creatorFee;
      pool.reserve0 -= amountOut;
      pool.reserve1 += swapAmount;

      pool.price += providerFees * 1e18 / pool.halfReserve;

      amountOut -= feeAmount;
    }

    if(pool.reserve1 == pool.halfReserve) {
      pool.reserve0 = pool.price * pool.halfReserve / 1e18;
    }

    if(sellAmount > 0) {
      uint256 sellValue = sellAmount * pool.price / 1e18;
      pool.reserve0 -= sellValue;
      pool.reserve1 += sellAmount;
      amountOut += sellValue;
    }

    if(amountOut < amountOutMin) revert LessThanAmountOutMin();

    TransferHelper.safeTransferETH(to, amountOut);

    emit Sell(id, amountIn, amountOut);
  }


  function setFeeRecipient(address _feeRecipient) external {
    require(msg.sender == dev);
    feeRecipient = _feeRecipient;
  }

  function setFeeTier(uint256 tier, bool b) external {
    require(tier <= 1000);
    require(msg.sender == dev);
    feeTiers[tier] = b;
  }

  function withdrawProtocolFees() external nonReentrant {
    uint256 fees = accProtocolFees;
    accProtocolFees = 0;
    TransferHelper.safeTransferETH(feeRecipient, fees);
  }

  function withdrawCreatorFees(uint160 id) external nonReentrant {
    Pool storage pool = pools[id];
    uint256 fees = pool.creatorFees;
    pool.creatorFees = 0;
    TransferHelper.safeTransferETH(pool.creator, fees);
  }

  function onERC1155Received(
    address operator,
    address from,
    uint256 id,
    uint256 amount,
    bytes calldata data
  ) public override returns (bytes4) {
    if(msg.sender != ethrunes) revert InvalidSender();
    uint8 command = uint8(data[0]);
    // sell
    if(command == 1) {
      address recipient;
      uint256 amountOutMin;
      uint256 deadline;
      assembly {
        recipient := calldataload(add(data.offset, 0x1))
        amountOutMin := calldataload(add(data.offset, 0x21))
        deadline := calldataload(add(data.offset, 0x41))
      }
      _sell(uint160(id), recipient, amount, amountOutMin, deadline);

    } else if(command == 2) { // createPool
      uint256 price;
      uint256 limitPerBuy;
      uint256 limitPerSell;
      uint256 fee;
      address creator;
      assembly {
        price := calldataload(add(data.offset, 0x1))
        limitPerBuy := calldataload(add(data.offset, 0x21))
        limitPerSell := calldataload(add(data.offset, 0x41))
        fee := calldataload(add(data.offset, 0x61))
        creator := calldataload(add(data.offset, 0x81))
      }

      _createPool(
        uint160(id), 
        amount,
        price,
        limitPerBuy,
        limitPerSell,
        fee,
        creator
      );
    } else {
      revert InvalidCall();
    }

    return this.onERC1155Received.selector;
  }

  function onERC1155BatchReceived(
    address,
    address,
    uint256[] calldata,
    uint256[] calldata,
    bytes calldata
  ) public override returns (bytes4) {
    revert NotSupportBatchReceivedCallback();
  }
}