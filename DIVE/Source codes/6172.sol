// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

abstract contract Context {
  function _msgSender() internal view virtual returns (address ) {
    return msg.sender;
  }

  function _msgData() internal view virtual returns (bytes memory) {
    this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
    return msg.data;
  }
}
abstract contract Ownable is Context {
  address private _owner;
  address private _previousOwner;
  uint256 private _lockTime;

  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

  /**
   * @dev Initializes the contract setting the deployer as the initial owner.
   */
  constructor()  {
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
    require(_owner == _msgSender(), 'Ownable: caller is not the owner');
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
    require(newOwner != address(0), 'Ownable: new owner is the zero address');
    emit OwnershipTransferred(_owner, newOwner);
    _owner = newOwner;
  }

  function geUnlockTime() public view returns (uint256) {
    return _lockTime;
  }

  //Locks the contract for owner for the amount of time provided
  function lock(uint256 time) public virtual onlyOwner {
    _previousOwner = _owner;
    _owner = address(0);
    _lockTime = block.timestamp + time;
    emit OwnershipTransferred(_owner, address(0));
  }

  //Unlocks the contract for owner when _lockTime is exceeds
  function unlock() public virtual {
    require(
      _previousOwner == msg.sender,
      "You don't have permission to unlock"
    );
    require(block.timestamp > _lockTime, 'Contract is locked until 7 days');
    emit OwnershipTransferred(_owner, _previousOwner);
    _owner = _previousOwner;
  }
}

interface IERC20 {
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns the amount of tokens owned by `account`.
   */
  function balanceOf(address account) external view returns (uint256);

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
  function allowance(address owner, address spender)
    external
    view
    returns (uint256);

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
  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) external returns (bool);

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
contract swaper is Ownable{


    IERC20 private oldTokenInstance;
    IERC20 private  newTokenInstance;
    address public holderWallet;
    // Events
    event TokensSwapped(address indexed user, uint256 amount);
    event TokensWithdrawn(address indexed owner, address token, uint256 amount);

    constructor(address _tokenA,address _tokenB)  {

        oldTokenInstance = IERC20(_tokenA);
        newTokenInstance = IERC20(_tokenB);
    
    }

    function swapTokens(uint256 amount) external{
        uint256 balanceBeforeTransfer = oldTokenInstance.balanceOf(address(this));
        bool transferStatus = oldTokenInstance.transferFrom(msg.sender,address(this),amount);         //make sure to approve the required amount
        uint256 balanceAfterTransfer = oldTokenInstance.balanceOf(address(this));
        require(balanceAfterTransfer - balanceBeforeTransfer  == amount,"Balance transfer failed");
        newTokenInstance.transferFrom(holderWallet,msg.sender,amount);

	emit TokensSwapped(msg.sender, amount);
    }

    function withdrawERC20(IERC20 token, uint256 amount) external onlyOwner{ 
        
        uint256 erc20balance = token.balanceOf(address(this));
        require(amount <= erc20balance, "balance is low");
        token.transfer(owner(), amount);
	emit TokensWithdrawn(owner(), address(token), amount);
    }

    function withdrawETH() external onlyOwner {
        uint256 amountETH = address(this).balance;
        payable(owner()).call{value: amountETH}('');
    }
        
    function changeHolderWallet(address _address) external onlyOwner{
        holderWallet = _address;
    }   

}