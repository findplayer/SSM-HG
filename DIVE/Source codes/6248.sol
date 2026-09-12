// SPDX-License-Identifier: MIT


// Company: Decrypted Labs
/// @title IAMDIVINITY
// @author Rabeeb Aqdas 
/// @dev Implements a referral system where users can refer others and earn rewards based on the membership purchase price.
/// @notice This contract manages a membership system with referral rewards, allowing users to buy memberships and earn rewards for referrals.

pragma solidity >=0.8.19;


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

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)




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




interface IERC20 {

    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 value) external;

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external;

    function transferFrom(address from, address to, uint value) external;
}


interface IROUTER02 {

  function getAmountsIn(
  uint amountOut, 
  address[] calldata path
  )  external view returns (uint[] memory amounts);

  function swapExactETHForTokens(
    uint amountOutMin, 
    address[] calldata path, 
    address to, 
    uint deadline
    ) external payable returns (uint[] memory amounts);

  function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    address[] calldata path,
    address to,
    uint256 deadline
) external returns (uint256[] memory amounts);
}

interface IFactory {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
}

/// @notice Error thrown when a user tries to refer themselves.
error CannotReferYourself();

/// @notice Error thrown when a user does not have enough funds to perform a transaction.
error NotEnoughMoney();

/// @notice Error thrown when an invalid level is provided for a function that requires level specification.
error InvalidLevel();

/// @notice Error thrown when a user who has already bought a membership tries to buy it again.
error AlreadyBoughtMemberShip();

/// @notice Error thrown when a user try to buy a membership with non supported currency
error  CurrencyNotSupported();

contract IAMDIVINITY is Ownable {

    /// @notice Structure representing a user in the IAMDIVINITY system.
    /// @dev Contains the user's referral address and a boolean indicating if they bought a membership.
    struct User {
        address referralAddr; // Address of the user who referred this user
        uint256[2] levelEarnings; // level-wise earnings of the user
        bool boughtMembership; // Whether the user has bought a membership
        uint256 totalSales; // Total sales of the user
    }

    /// @notice The address of the Uniswap V2 Router.
    address constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    /// @notice The address of the USDC token.
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// @dev A private instance of the Uniswap V2 Router for token swap functionalities.
    IROUTER02 private _helperRouter = IROUTER02(ROUTER);

    /// @dev Helper token contract for handling USDC transactions.
    IERC20 private _helperUSDC = IERC20(USDC); 
        
    /// @dev Wallet address for administrative funds.
    address private adminWallet;

    /// @notice The price for buying a membership.
    uint256 private price;
    
    /// @notice Total number of users who have bought a membership.
    uint256 private totalUsers;
    
    /// @dev Base constant used for percentage calculations.
    uint256 private constant BASE = 100;
    
    /// @dev Reward percentages for referrals, stored as [first level, second level].
    uint256[2] private rewardPercentages = [20, 10];
    
    /// @dev Stores information about each user, including referral data and membership status.
    mapping (address userAddress => User) private users;

    /// @dev Stores referral relationships in a hierarchical structure for reward calculations.
    mapping(uint256 level => mapping(address userAddress => address[])) private referrals_levels;

    /// @dev Maps token addresses to a boolean indicating whether the token is an accepted currency in the contract.
    mapping (address tokenAddress => bool) private currencies;
    
    /// @notice Emitted when the membership price is changed.
    /// @param _oldPrice The previous price.
    /// @param _newPrice The new price set.
    event PriceChanged(uint256 _oldPrice, uint256 _newPrice);
    
    /// @notice Emitted when the administrative wallet is changed.
    /// @param _oldWallet The previous wallet address.
    /// @param _newWallet The new wallet address set.
    event WalletChanged(address _oldWallet, address _newWallet);
    
    /// @notice Emitted when a user buys a membership.
    /// @param _user The address of the user who bought the membership.
    /// @param _referee The address of the user who referred.
    /// @param _price The price of the membership bought.
    /// @param _timestamp The timestamp when the membership was bought.
    event BoughtMemberShip(address indexed _user,address indexed _referee,uint256 _price, uint256 _timestamp);

    /// @notice Constructor to set up the IAMDIVINITY contract.
    /// @param _adminWallet The wallet address where administrative funds are sent.
    /// @param _supportedCurrencies Array of addresses for the initially supported currency tokens.
    /// @param _price The price of buying a membership.
    constructor(address _adminWallet, address[6] memory _supportedCurrencies , uint256 _price) Ownable(_msgSender()) {
     adminWallet = _adminWallet;    
     price = _price;
    for(uint256 i ; i < _supportedCurrencies.length ; i = unsafe_inc(i)) {
      currencies[_supportedCurrencies[i]] = true;
    }  
    }

    /// @notice Fallback function to accept Ether payments.
    receive() external payable {}

    /// @notice Allows a user to buy a membership and sets their referral, if applicable.
    /// @param _referralAddr The address of the referrer.
    /// @param _tokenAddress The address of the token in which you want to pay.
    /// @dev Emits a BoughtMemberShip event upon successful membership purchase.
    function buyMembership(address _referralAddr, address _tokenAddress) external payable {
      if(!currencies[_tokenAddress]) revert CurrencyNotSupported();
      address _sender = _msgSender();
        User memory user = users[_sender];
        if(user.boughtMembership) revert AlreadyBoughtMemberShip();
        address _adminWallet = adminWallet;
        if(_sender != _adminWallet) {
        _referralAddr = _referralAddr == address(0) ? _adminWallet : _referralAddr; 
        _addReferee(_sender, _referralAddr);
        }

        _buyMemberShip(_sender, _referralAddr, _tokenAddress, msg.value);
    }

    /// @notice Handles the purchase of membership for a user.
    /// @dev Transfers USDC from the user to the owner, adjusts membership status and distributes rewards if applicable.
    /// @param _user The address of the user buying the membership.
    /// @param _referralAddr The referral address for reward distribution.
    /// @param _tokenAddress The token address for payment.
    /// @param _amount The amount of ethers sent by the user.
    function _buyMemberShip(address _user, address _referralAddr, address _tokenAddress, uint256 _amount) private {
      uint256 _price = price; 
      uint256 _amountOut;
      if(_tokenAddress != USDC) {
      address[] memory _path = new address[](2);
      _path[0] = _tokenAddress;
      _path[1] = USDC;
      uint256 estimatedAmount = getQuote(_tokenAddress);
      if(_amount > 0) {
      require(_amount >= estimatedAmount,"Not enough amount");  
      _amountOut = _helperRouter.swapExactETHForTokens{value: _amount}(price, _path, address(this), block.timestamp)[1];
      }else {
      IERC20 _helperERC20 = IERC20(_tokenAddress);
      if(_helperERC20.balanceOf(_user) < estimatedAmount) revert NotEnoughMoney();
      _helperERC20.transferFrom(_msgSender(), address(this), estimatedAmount);

      if(_helperERC20.allowance(address(this),ROUTER) == 0) 
      _helperERC20.approve(ROUTER, type(uint256).max); 
      _amountOut = _helperRouter.swapExactTokensForTokens(estimatedAmount, price, _path, address(this), block.timestamp)[1];
      }
      if(_amountOut < _price) revert NotEnoughMoney();
      
      }else {
        if(_helperUSDC.balanceOf(_user) < _price) revert NotEnoughMoney();
        _helperUSDC.transferFrom(_msgSender(), address(this), _price);
      }
        _referralAddr = getUserDetail(_user).referralAddr;
        if(_referralAddr != address(0)) _sendRewards(_referralAddr, _price);
        uint256 amountToBeSend = _helperUSDC.balanceOf(address(this));
        
        _helperUSDC.transfer(owner(), amountToBeSend);
        users[_user].boughtMembership = true;
        emit BoughtMemberShip(_user, _referralAddr, _price,block.timestamp);

    }

    /// @notice Retrieves the required amount of input tokens to obtain the fixed price in USDC.
    /// @dev Uses a helper router to get the amount of input tokens needed for the desired output of USDC.
    /// @param tokenIn The address of the input token for which the quote is being calculated.
    /// @return amountOut The amount of the input token required to obtain the fixed price in USDC.
    function getQuote(
      address tokenIn
    ) public view returns (uint256 amountOut) {
      address _usdc = USDC;
      uint256 _price = price;
      if(tokenIn != _usdc) {
      address[] memory _path = new address[](2);
      _path[0] = tokenIn;
      _path[1] = _usdc;
      amountOut = _helperRouter.getAmountsIn(_price, _path)[0];
      }else amountOut = _price;
    }

    /// @notice Adds a new referee under a referrer.
    /// @dev Stores the referral relationship and increments the total user count.
    /// @param _user The address of the new user (referee).
    /// @param _referralAddr The address of the referrer.   
    function _addReferee(address _user, address _referralAddr) private {
        if(_referralAddr == _user) revert CannotReferYourself();
        users[_user].referralAddr = _referralAddr;
        address upline = _referralAddr;
        for (uint256 i ; i < 2; i = unsafe_inc(i)) {
            referrals_levels[i][upline].push(_user);
            upline = getUserDetail(upline).referralAddr;
            if (upline == address(0)) break;            
        }
        totalUsers = totalUsers + 1;
    }

    /// @notice Sends referral rewards up the referral chain.
    /// @dev Transfers a percentage of the purchase price as a reward to referrers.
    /// @param _referralAddr The address of the direct referrer.
    /// @param _price The price based on which rewards are calculated.
    function _sendRewards(address _referralAddr, uint256 _price) private {
      
       uint256[2] memory _rewardPercentages = rewardPercentages;
       address upline = _referralAddr;   
           
        for(uint256 i ; i < 2; i = unsafe_inc(i)) {
          uint256 reward = _price *_rewardPercentages[i] / BASE;
          _helperUSDC.transfer(upline, reward);
          User memory _user = users[upline];
          _user.totalSales = _user.totalSales + 1;
          _user.levelEarnings[i] = _user.levelEarnings[i] + reward;
          users[upline] = _user;
          upline = getUserDetail(upline).referralAddr;
          if (upline == address(0)) break;
        }

    }

    /// @notice Allows the owner to change the price of the membership.
    /// @dev Emits a PriceChanged event upon changing the price.
    /// @param _newPrice The new membership price.
    function changePrice(uint256 _newPrice) external onlyOwner {
        require(_newPrice > 0, "price can't be zero");
        emit PriceChanged(price, _newPrice);
        price = _newPrice;
  }

    /// @notice Allows the owner to change the reward percentages.
    /// @param _rewardPercentages The new membership price.
    function changerewardPercentages(uint256[2] memory _rewardPercentages) external onlyOwner {
        rewardPercentages = _rewardPercentages;
  }

    /// @notice Allows the owner to change the admin wallet address.
    /// @dev Emits a WalletChanged event upon changing the admin wallet.
    /// @param _newWallet The new admin wallet address.
    function changeAdminWallet(address _newWallet) external onlyOwner {
        require(_newWallet != address(0), "Invalid Address");
        emit WalletChanged(adminWallet, _newWallet);
        adminWallet = _newWallet;
  }

    /// @notice Updates the status of a token in the list of accepted currencies.
    /// @dev Allows the owner to enable or disable a token as an accepted currency.
    /// @param _tokenAddress The address of the token to be updated.
    /// @param _action The action to be taken (true to enable, false to disable).
    function updateCurrencies(address _tokenAddress, bool _action) external onlyOwner {
       require(currencies[_tokenAddress] != _action, "Already in the same state");
        currencies[_tokenAddress] = _action;
  }

    /// @notice Retrieves the list of referrals for a user at a specific level.
    /// @dev Level is expected to be 0 or 1.
    /// @param _level The level of referrals to retrieve.
    /// @param _user The user whose referrals are being queried.
    /// @return The list of referral addresses at the specified level.
    function getReferralsByLevel(uint256 _level, address _user) external view returns(address[] memory) {
    if(_level > 1) revert InvalidLevel();
    return referrals_levels[_level][_user];
  }

    /// @notice Retrieves the details of a specific user.
    /// @param _user The user whose address is being queried.
    /// @return The detail of the specified user.
    function getUserDetail(address _user) public view returns(User memory) {
    return users[_user];
  }

    /// @notice Retrieves the percentages of reward in each level.
    /// @return The reward percentages of each level.
    function getRewardPercentages() external view returns(uint256[2] memory) {
    return rewardPercentages;
  }

    /// @notice Retrieves the status of currencies.
    /// @param _currency the address of currency which is being queried.
    /// @return The status of the currency.
    function getCurrencyStatus(address _currency) external view returns(bool) {
    return currencies[_currency];
  }

    /// @notice Retrieves the details of the contract.
    /// @dev this function will return the total number of users, price, address of admin and reward percentages of the contract.
    function getDetails() external view returns(uint256 _totalUsers,uint256 _price, address _adminWallet, uint256[2] memory _rewardPercentages) {
    _totalUsers = totalUsers;
    _price = price;
    _adminWallet = adminWallet;
    _rewardPercentages = rewardPercentages;
  }

    /// @notice An internal function to increment a uint256 safely.
    /// @dev Increments the input value by 1 without causing overflow.
    /// @param i The value to be incremented.
    /// @return The incremented value.
    function unsafe_inc(uint256 i) internal pure returns(uint256) {
    unchecked {
        return  i + 1;
    }
  }

}