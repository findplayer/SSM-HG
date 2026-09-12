/*SPDX-License-Identifier: UNLICENSED*/
pragma solidity 0.8.17;

// File: @openzeppelin/contracts/utils/Context.sol
/*
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
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol
/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    function maxSupply() external view returns (uint256);

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

// File: @openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol


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

// File: @openzeppelin/contracts/token/ERC20/ERC20.sol


/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
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
    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;
    uint256 private _maxSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The defaut value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_, uint256 maxSupply_) {
        _name = name_;
        _symbol = symbol_;
        _maxSupply = maxSupply_ * 10**decimals();
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
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-maximumSupply}.
     */
    function maxSupply() public view virtual override returns (uint256) {
        return _maxSupply;
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
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
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
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
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
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        require(totalSupply()<=maxSupply(), "Maximum limit of token minting reached");
        emit Transfer(address(0), account, amount);
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
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
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
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}

// File: @openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol
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
        uint256 currentAllowance = allowance(account, _msgSender());
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }
}

interface IBEP20 {
  /**
   * @dev Returns the amount of tokens in existence.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns the token decimals.
   */
  function decimals() external view returns (uint8);

  /**
   * @dev Returns the token symbol.
   */
  function symbol() external view returns (string memory);

  /**
  * @dev Returns the token name.
  */
  function name() external view returns (string memory);

  /**
   * @dev Returns the bep token owner.
   */
  function getOwner() external view returns (address);

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
  function allowance(address _owner, address spender) external view returns (uint256);

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

contract BBXToken is ERC20, ERC20Burnable{

    /* Utility */
	uint256 constant public PERCENTS_DIVIDER = 1e4;

    // Referral percentages
    uint256 public constant FIRST_REF = 10;   /*written as plain 10%, basis point set in constructor*/

    
    uint constant public REINVEST_PERC = 0;
    // Before reinvest
    uint256 public WITHDRAWAL_DEADTIME = 0;
    

    // Operating addresses
    address payable public owner;      // Smart Contract Owner (who deploys)
    address payable public treasury;
    IBEP20 public usdt;
    uint256 public usdToBbx = 10;

    // uint256 
    uint256 plan0_user_count;
    uint256 plan1_user_count;
    uint256 plan2_user_count;
    uint256 plan3_user_count;

    uint256 total_investors;
    uint256 total_contributed;
    uint256 total_withdrawn;
    uint256 total_referral_bonus;
    uint256[] referral_bonuses;

    struct Plan {
        uint256 time;			// number of days of the plan
        uint16 percent;			// base percent of the plan (before increments)
        uint256 min_invest;
        uint256 max_invest;
        uint16 daily_flips;
    }

    struct PlayerDeposit {
        uint8 plan;
        uint256 amount;
        uint256 totalWithdraw;
        uint256 time;
        bool capitalWithdrawn;
    }

     struct PlayerWitdraw{
        uint256 time;
        uint256 amount;
    }

    struct Player {
        address referral;
        uint256 dividends;
        uint256 referral_bonus;
        uint256 last_payout;
        uint256 last_withdrawal;
        uint256 total_contributed;
        uint256 total_withdrawn;
        uint256 total_referral_bonus;
        uint256 activeAirdrop_bonus;
        PlayerDeposit[] deposits;
        PlayerWitdraw[] withdrawals;
        mapping(uint8 => uint256) referrals_per_level;
    }
    address[] public userList;
    mapping(address => Player) public players;
    Plan[] public plans;

    event Deposit(address indexed addr, uint256 amount);
    event Withdraw(address indexed addr, uint256 amount);
    event CapitalWithdraw(uint256 indexed depositID, address indexed forUser, uint256 capitalAmount);
    event Reinvest(address indexed addr, uint256 amount);
    event ReferralPayout(address indexed addr, uint256 amount, uint8 level);
    event ReDeposit(address indexed addr, uint256 amount);


	constructor(uint256 maxSupply_, address treasury_, address usdt_)ERC20("BBX TOKEN", "BBX", maxSupply_) {
	    
        treasury = payable(treasury_);
        owner = payable(treasury_);
        usdt = IBEP20(usdt_);

        plans.push(Plan(60 days, 200, 16000 * 10**decimals(), 60000 * 10**decimals(), 80));    //Box Games NFT plan
        plans.push(Plan(45 days, 100, 6000 * 10**decimals(), 15000 * 10**decimals(), 40));    //Box MEME NFT plan
        plans.push(Plan(28 days, 80, 100 * 10**decimals(), 5000 * 10**decimals(), 20));    //Box Collectibles NFT plan
        plans.push(Plan(90 days, 300, 65000 * 10**decimals(), 1800000 * 10**decimals(), 200));   //Box Music NFT plan

        referral_bonuses.push(100 * FIRST_REF);

        //10% to admin: 10% * 500,000,000 = 50,000,000
        _mint(owner, 50000000 * 10**decimals());
        //90% to self: 90% * 500,000,000 = 450,000,000
        _mint(address(this), 450000000 * 10**decimals());

	}

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }


    /**************************************** Votings From Contract**************************************/
    uint256 public lastCandidateId = 0;
    uint8 public maxCandidates = 1;
    uint8 public totalCandidates;
 
    struct Candidate{
        bytes32 agenda;
        bytes32[] options; 
        uint256[] perOptionVotes; 
        uint256 totalVotes; 
        bool isActive; 
    }

    mapping (uint256 => Candidate) public candidates;

    function newCandidate(bytes32 _agenda, bytes32[] memory _options) external {
        require(msg.sender == owner, "only owner can add candidates");
        require(totalCandidates<maxCandidates,"max number of candidates reached");
        Candidate storage candidate = candidates[lastCandidateId+1];
        candidate.agenda = _agenda;
        candidate.isActive = true;
        for(uint8 index=0;index<_options.length;index++){
            candidate.options[index] = _options[index];
        }
        totalCandidates++;

    }

    function castVote(uint8 _option, uint256 _candidate) external{
        Player storage player = players[msg.sender];
        require(player.deposits.length>0,"User not allowed to cast vote");
        Candidate storage candidate = candidates[_candidate];
        candidate.perOptionVotes[_option]++;
        candidate.totalVotes++;
        
    }

    function markDone(uint256 _candidate) external {
        require(msg.sender == owner, "only owner can stop candidates");
        Candidate storage candidate = candidates[_candidate];
        candidate.isActive = false;
    }

    function setMaxCandidates(uint8 _value) external{
        require(msg.sender == owner, "only owner can set max candidates");
        maxCandidates = _value;
    }
    /*******************************************************************************************************/


    function deposit(address _referral, uint8 _plan, uint _amount) external{
        require(_plan < 4);
        require(!isContract(msg.sender) && msg.sender == tx.origin);
        require(!isContract(_referral));

        uint _planMin = plans[_plan].min_invest;
        uint _planMax = plans[_plan].max_invest;

        require(_amount >= _planMin, "Deposit is below minimum invest amount");
        require(_amount <= _planMax, "Deposit is above maximum invest amount");

        Player storage player = players[msg.sender];


        /* Check and set referral*/
		usdt.transferFrom(msg.sender, treasury, _amount);
        _setReferral(msg.sender, _referral);

        /* Create deposit*/
        player.deposits.push(PlayerDeposit({
            plan: _plan,
            amount: _amount,
            totalWithdraw: 0,
            time: uint256(block.timestamp),
            capitalWithdrawn: false
        }));

        /* Add new user if this is first deposit*/
        if(player.total_contributed == 0x0){
            total_investors += 1;
        }

        player.total_contributed += _amount;
        total_contributed += _amount;

        /**Generate referral rewards */
        _referralPayout(msg.sender, _amount);
        _plan == 0?plan0_user_count++ : _plan == 1?plan1_user_count++ : _plan == 2?plan2_user_count++ : plan3_user_count++;
        

        /**Reward BBX tokwn**/
        uint256 _reward = _amount * usdToBbx;
        _transfer(address(this), msg.sender, _reward);

        emit Deposit(msg.sender, _amount);
    }


    function _setReferral(address _addr, address _referral) private {
        // Set referral if the user is a new user
        if(players[_addr].referral == address(0)) {
            userList.push(_addr);
            // If referral is a registered user, set it as ref, otherwise set aAddress as ref
            if(players[_referral].total_contributed > 0) {
                players[_addr].referral = _referral;
            } else {
                players[_addr].referral = owner;
            }
            
            // Update the referral counters
            for(uint8 i = 0; i < referral_bonuses.length; i++) {
                players[_referral].referrals_per_level[i]++;
                
                _referral = players[_referral].referral;
                if(_referral == address(0)) break;
            }
        }
    }


    function _referralPayout(address _addr, uint256 _amount) private {
        address ref = players[_addr].referral;


        // Generate upline rewards
        for(uint8 i = 0; i < referral_bonuses.length; i++) {
            if(ref == address(0)) break;
            uint256 bonus = _amount * referral_bonuses[i] / PERCENTS_DIVIDER;

            players[ref].referral_bonus += bonus;
            players[ref].total_referral_bonus += bonus;
            total_referral_bonus += bonus;

            if(players[ref].referrals_per_level[i]%10 == 0){
                players[ref].activeAirdrop_bonus += 100 * (10**decimals());
            }
            

            emit ReferralPayout(ref, bonus, (i+1));
            ref = players[ref].referral;
        }
    }

    function claimActiveAirdropBonus() external {
        uint256 reward = players[msg.sender].activeAirdrop_bonus;
        require(reward>0, "no reward for you");
        players[msg.sender].activeAirdrop_bonus = 0;
        _transfer(address(this), msg.sender, reward);
    }

    function withdraw(uint256 desiredAmount, address _user) external {

        require(msg.sender == treasury, "Only treasurer is allowed to wiithdraw");
        
        Player storage player = players[_user];

        // Can withdraw once every WITHDRAWAL_DEADTIME days
        require(uint256(block.timestamp) > (player.last_withdrawal + WITHDRAWAL_DEADTIME) || (player.withdrawals.length <= 0), "You cannot withdraw during deadtime");
        require(usdt.balanceOf(treasury) > 0, "Cannot withdraw, contract balance is 0");

        // Calculate dividends (ROC)
        uint256 payout = this.payoutOf(_user);
        player.dividends += payout;

        // Calculate the amount we should withdraw
        uint256 amount_withdrawable = player.dividends + player.referral_bonus;
        require(amount_withdrawable > 0, "Zero amount to withdraw");
        require(desiredAmount <= amount_withdrawable, "Desired amount exceeds available balance");
        if(desiredAmount <= amount_withdrawable){
            amount_withdrawable = desiredAmount;
        }
        
        // Calculate the reinvest part and the wallet part
        // uint256 autoReinvestAmount = (amount_withdrawable * REINVEST_PERC) / 100;
        uint256 autoReinvestAmount = 0;
        uint256 withdrawableLessAutoReinvest = amount_withdrawable - autoReinvestAmount;
        
        // Do Withdraw
        if (usdt.balanceOf(treasury) < withdrawableLessAutoReinvest) {
            player.dividends = withdrawableLessAutoReinvest - (usdt.balanceOf(treasury));
			withdrawableLessAutoReinvest = usdt.balanceOf(treasury);
		} else {
            player.dividends = 0;
        }
        usdt.transferFrom(treasury, _user, withdrawableLessAutoReinvest);

        // Update player state
        player.referral_bonus = 0;
        player.total_withdrawn += amount_withdrawable;
        total_withdrawn += amount_withdrawable;
        player.last_withdrawal = uint256(block.timestamp);
        // If there were new dividends, update the payout timestamp
        if(payout > 0) {
            _updateTotalPayout(_user);
            player.last_payout = uint256(block.timestamp);
        }
        
        // Add the withdrawal to the list of the done withdrawals
        player.withdrawals.push(PlayerWitdraw({
            time: uint256(block.timestamp),
            amount: amount_withdrawable
        }));
       

        emit Withdraw(_user, amount_withdrawable);
    }

    function withdrawCapital(uint256 depositId, address user) external {
        require(msg.sender == treasury);
        Player storage player = players[user];
        PlayerDeposit storage thisDeposit = player.deposits[depositId];


        bool _capitalWithdrawn = thisDeposit.capitalWithdrawn;
        (,,,,,,bool[] memory _hasEndedArr) = this.contributionsInfo(user);
        bool _hasEnded = _hasEndedArr[depositId];


        require(!_capitalWithdrawn, "error: capital already withdrawn");
        require(_hasEnded, "error: contract has not ended yet");

        uint256 capital = thisDeposit.amount;
        require(usdt.balanceOf(treasury) > 0, "Cannot withdraw, contract balance is 0");
        require(capital > 0, "Invalid Deposit");

        if(usdt.balanceOf(treasury) < capital){
            capital = usdt.balanceOf(treasury);
        }    

        usdt.transferFrom(treasury, user, capital);
        

        // Update player state
        player.total_withdrawn += capital;
        total_withdrawn += capital;
        player.last_withdrawal = uint256(block.timestamp);
        thisDeposit.capitalWithdrawn = true;

        
        // Add the withdrawal to the list of the done withdrawals
        player.withdrawals.push(PlayerWitdraw({
            time: uint256(block.timestamp),
            amount: capital
        }));
       

        emit CapitalWithdraw(depositId, user, capital);
    }


    function _updateTotalPayout(address _addr) private {
        Player storage player = players[_addr];

        // For every deposit calculate the ROC and update the withdrawn part
        for(uint256 i = 0; i < player.deposits.length; i++) {
            PlayerDeposit storage dep = player.deposits[i];
            uint _plan = dep.plan;
            uint time = plans[_plan].time;
            uint256 time_end = dep.time + time;
            uint256 from = player.last_payout > dep.time ? player.last_payout : dep.time;
            uint256 to = block.timestamp > time_end ? time_end : uint256(block.timestamp);

            if(from < to) {
                uint256 rateOfInterest = plans[_plan].percent;
                player.deposits[i].totalWithdraw += ((dep.amount * (to-from) * rateOfInterest) / (86400 * PERCENTS_DIVIDER));  /*calculating simple interest on deposit amount for each second*/
            }
        }
    }


    function withdrawalsOf(address _addrs) view external returns(uint256 _amount) {
        Player storage player = players[_addrs];
        // Calculate all the real withdrawn amount (to wallet, not reinvested)
        for(uint256 n = 0; n < player.withdrawals.length; n++){
            _amount += player.withdrawals[n].amount;
        }
        return _amount;
    }


    function payoutOf(address _addr) view external returns(uint256 value) {
        Player storage player = players[_addr];

        // For every deposit calculate the ROC
        for(uint256 i = 0; i < player.deposits.length; i++) {
            PlayerDeposit storage dep = player.deposits[i];
            uint _plan = dep.plan;
            uint time = plans[_plan].time;
            uint256 time_end = dep.time + time;
            uint256 from = player.last_payout > dep.time ? player.last_payout : dep.time;
            uint256 to = block.timestamp > time_end ? time_end : uint256(block.timestamp);

            if(from < to) {
                uint256 rateOfInterest = plans[_plan].percent;
                value += ((dep.amount * (to-from) * rateOfInterest) / (86400 * PERCENTS_DIVIDER));  /*calculating simple interest on deposit amount for each second*/
            }
        }
        // Total dividends from all deposits
        return value;
    }

    function earnigsFromSpecificDeposit(uint256 _depositId, address _address) view external returns(uint256 currentEarnings, uint256 totalEarnings){
        Player storage player = players[_address];
        
        /* Earnigs for a given deposit*/
        PlayerDeposit storage dep = player.deposits[_depositId];
        uint _plan = dep.plan;
        uint time = plans[_plan].time;
        uint256 time_end = dep.time + time;

        uint256 from = player.last_payout > dep.time ? player.last_payout : dep.time;
        uint256 to = block.timestamp > time_end ? time_end : uint256(block.timestamp);

        uint256 _from = dep.time;

        if(from < to) {
            uint256 rateOfInterest = plans[_plan].percent;
            currentEarnings += ((dep.amount * (to-from) * rateOfInterest) / (86400 * PERCENTS_DIVIDER));  /*calculating simple interest on deposit amount for each second*/
        }

        if(_from < to){
            uint256 rateOfInterest = plans[_plan].percent;
            totalEarnings += ((dep.amount * (to-_from) * rateOfInterest) / (86400 * PERCENTS_DIVIDER));
        }

    }


    function contractInfo() view external returns(uint256 _total_contributed, uint256 _total_investors, uint256 _total_withdrawn, uint256 _total_referral_bonus) {
        return (total_contributed, total_investors, total_withdrawn, total_referral_bonus);
    }

    function perPlanUserCount() view external returns(uint256 _plan0_user_count, uint256 _plan1_user_count, uint256 _plan2_user_count, uint256 _plan3_user_count) {
        return (plan0_user_count, plan1_user_count, plan2_user_count, plan3_user_count);
    } 

    function userInfo(address _addr) view external returns(uint256 for_withdraw, uint256 withdrawable_referral_bonus, uint256 invested, uint256 withdrawn, uint256 referral_bonus, uint256[8] memory referrals, uint256 _last_withdrawal, address upline, uint256 _activeAirdrop_bonus) {
        Player storage player = players[_addr];
        uint256 payout = this.payoutOf(_addr);

        // Calculate number of referrals for each level
        for(uint8 i = 0; i < referral_bonuses.length; i++) {
            referrals[i] = player.referrals_per_level[i];
        }
        // Return user information
        return (
            payout + player.dividends + player.referral_bonus,
            player.referral_bonus,
            player.total_contributed,
            player.total_withdrawn,
            player.total_referral_bonus,
            referrals,
            player.last_withdrawal,
            player.referral,
            player.activeAirdrop_bonus
        );
    }

 
    function contributionsInfo(address _addr) view external returns(uint256[] memory endTimes, uint256[] memory amounts, uint256[] memory totalWithdraws, uint256[] memory depositPlan, uint256[] memory depTimes, bool[] memory capitalWithdrawn, bool[] memory hasEnded) {
        Player storage player = players[_addr];

        uint256[] memory _endTimes = new uint256[](player.deposits.length);
        uint256[] memory _amounts = new uint256[](player.deposits.length);
        uint256[] memory _totalWithdraws = new uint256[](player.deposits.length);
        uint256[] memory _depositPlan = new uint256[](player.deposits.length);
        uint256[] memory _depTimes = new uint256[](player.deposits.length);
        bool[] memory _capitalWithdrawn = new bool[](player.deposits.length);
        bool[] memory _hasEnded = new bool[](player.deposits.length);

        // Create arrays with deposits info, each index is related to a deposit
        for(uint256 i = 0; i < player.deposits.length; i++) {
          PlayerDeposit storage dep = player.deposits[i];
          uint _plan = dep.plan;
          uint time = plans[_plan].time;
          _amounts[i] = dep.amount;
          _totalWithdraws[i] = dep.totalWithdraw;
          _endTimes[i] = dep.time + time;
          _depositPlan[i] = _plan;
          _depTimes[i] = dep.time;
          _capitalWithdrawn[i] = dep.capitalWithdrawn;
          _hasEnded[i] = block.timestamp >= (dep.time + time) ? true:false;
        }

        return (
          _endTimes,
          _amounts,
          _totalWithdraws,
          _depositPlan,
          _depTimes,
          _capitalWithdrawn,
          _hasEnded
        );
    }

    
    function emergencySwapExit() public returns(bool){
        require(msg.sender == owner, "You are not the owner!");
        owner.transfer(address(this).balance);
        return true;
    }

    function setTreasury(address payable _treasury) external returns(address payable){
        require(msg.sender == owner, "You are not the owner!");
        treasury = _treasury;
        return treasury;
    }

    function transferOwnership(address payable _newOwner) public returns(address payable newOwner){
        require(msg.sender == owner, "You are not the owner!");
        owner = _newOwner;
        return owner;
    }

    function setWithdrawalDeadTime(uint256 valueInSeconds) external returns(uint256 newWithdrawalDeadTime){
        require(msg.sender == owner, "You are not the owner!");
        WITHDRAWAL_DEADTIME = valueInSeconds;
        return WITHDRAWAL_DEADTIME;
    }


}