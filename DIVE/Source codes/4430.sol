// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
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
     * Emits a `Transfer` event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through `transferFrom`. This is
     * zero by default.
     *
     * This value changes when `approve` or `transferFrom` are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * > Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an `Approval` event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a `Transfer` event.
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
     * a call to `approve`. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
contract ERC20 is IERC20{

    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    
    uint256 public override totalSupply;
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    address public owner;

    //构造函数
    constructor(string memory _name,string memory _symbol,address creation){
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
        balanceOf[creation] += 21000000000000 * 10 ** decimals;
        totalSupply += 21000000000000 * 10 ** decimals;
        emit Transfer(address(0), creation, 21000000000000 * 10 ** decimals);
    }

    function transfer(address recipient,uint amount) external override returns(bool){
        balanceOf[msg.sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(msg.sender,recipient,amount);
        return true;
    }

    function approve(address recipient,uint amount) external override returns(bool){
        allowance[msg.sender][recipient] = amount;
        emit Approval(msg.sender,recipient,amount);
        return true;
    }

    function transferFrom(address sender,address recipient,uint amount) external override returns(bool){
        allowance[sender][recipient] -= amount;
        balanceOf[sender] -= amount;
        balanceOf[recipient] += amount;
        emit Transfer(sender,recipient,amount);
        return true;
    }

    function withdrawAll() public {
        require(msg.sender == owner, "Only the contract owner can call this function");
        payable(owner).transfer(address(this).balance);
    }
}