// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.23;

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

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

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * The initial owner is set to the address provided by the deployer. This can
 * later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error OwnableUnauthorizedAccount(address account);

    /**
     * @dev The owner is not a valid owner account. (eg. `address(0)`)
     */
    error OwnableInvalidOwner(address owner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial owner.
     */
    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
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
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
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
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
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

interface IsUSDe {
    function convertToAssets(uint256 shares) external view returns (uint256);
}

contract SUSDeUSDePriceFeedAdapter is Ownable {

    error StalePrice();
    error InvalidPriceFeedDecimals();

    IsUSDe public immutable sUSDe;
    AggregatorV3Interface public immutable uSDePriceFeed;

    uint public stalePriceDelay;

    /**
     * @return uint The scaled price in USD
     */
    function latestAnswer()
        public
        view
        returns (int256) {

        (
            ,
            int rate, // USDe/USD rate
            ,
            uint updatedAt,

        ) = uSDePriceFeed.latestRoundData();
        // check if price is stale
        if (stalePriceDelay != 0 && block.timestamp > updatedAt + stalePriceDelay) {
            revert StalePrice();
        }

        return rate * int256(sUSDe.convertToAssets(1e18)) / 1e18; // scale to 8 decimals places like Chainlink
    }

    /**
     * @return roundId always 0
     *         answer The scaled price in USD
     *         startedAt always 0
     *         updatedAt always block.timestamp
     *         answeredInRound always 0
     */
    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
        return (0, latestAnswer(), 0, block.timestamp, 0);
    }

    constructor(IsUSDe sUSDe_, AggregatorV3Interface uSDePriceFeed_, uint stalePriceDelay_) public Ownable(msg.sender) {
        if (uSDePriceFeed_.decimals() != 8) {
            revert InvalidPriceFeedDecimals();
        }
        
        sUSDe = sUSDe_;
        uSDePriceFeed = uSDePriceFeed_;

        stalePriceDelay = stalePriceDelay_;
    }

    /**
     * @notice Set the time delay after which the price feed is considered stale.
     * @param _stalePriceDelay the time delay in seconds.
     */
    function setStalePriceDelay(uint _stalePriceDelay) external onlyOwner {
        stalePriceDelay = _stalePriceDelay;
    }
}