// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// Interface for the ERC-20 standard for tokens.
interface IERC20 {
    // Returns the total token supply.
    function totalSupply() external view returns (uint256);

    // Returns the account balance of another account with address `account`.
    function balanceOf(address account) external view returns (uint256);

    // Transfers `amount` tokens to address `recipient`, and MUST fire the Transfer event.
    function transfer(address recipient, uint256 amount) external returns (bool);

    // Returns the amount which `spender` is still allowed to withdraw from `owner`.
    function allowance(address owner, address spender) external view returns (uint256);

    // Allows `spender` to withdraw from your account multiple times, up to the `amount` value.
    function approve(address spender, uint256 amount) external returns (bool);

    // Transfers `amount` tokens from `sender` to `recipient` given the from account has enough balance.
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    // Event emitted when tokens are transferred, including zero value transfers.
    event Transfer(address indexed from, address indexed to, uint256 value);

    // Event emitted when the allowance of a `spender` for an `owner` is set by a call to `approve`.
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data; }
}

// Contract to define ownership and allow transfer of ownership.
contract Ownable {
    address private _owner;

    // Event for ownership transfers.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    // Returns the address of the current owner.
    function owner() public view returns (address) {
        return _owner;
    }

    // Modifier to restrict access to owner-only functions.
    modifier onlyOwner() {
        require(_owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    // Transfers ownership of the contract to a new address.
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    // Allows the current owner to relinquish control of the contract.
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

// Main token contract implementing the ERC-20 interface and additional functionalities.
contract TurboFox is IERC20, Ownable {
    string public constant name = "Turbo Fox";
    string public constant symbol = "TFOX";
    uint8 public constant decimals = 18;
    uint256 private totalSupply_ = 2e9 * 10**uint256(decimals); // Initial supply of 2 billion tokens, with decimal support.

    uint256 public taxRate = 5; // Tax rate is 5% for transactions.
    uint256 public maxTransactionAmount = totalSupply_ / 100; // Max transaction amount set to 1% of total supply.

    mapping(address => uint256) private balances; // Track balances of token holders.
    mapping(address => mapping (address => uint256)) private allowed; // Track allowances for delegated transfer.
    mapping(address => bool) private taxExempt; // Track addresses exempt from tax.

    constructor() {
        balances[msg.sender] = totalSupply_; // Assign all tokens to contract creator.
        emit Transfer(address(0), msg.sender, totalSupply_);
    }

    // Returns the total token supply.
    function totalSupply() public view override returns (uint256) {
        return totalSupply_;
    }

    // Returns the balance of a token owner.
    function balanceOf(address tokenOwner) public view override returns (uint256) {
        return balances[tokenOwner];
    }

    // Transfer tokens to another address, applying tax if applicable.
    function transfer(address receiver, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[msg.sender], "Insufficient balance");
        require(numTokens <= maxTransactionAmount, "Exceeds max transaction amount");

        // Calculate tax if not exempt.
        uint256 tax = taxExempt[msg.sender] ? 0 : (numTokens * taxRate) / 100;
        uint256 tokensToTransfer = numTokens - tax;

        // Update balances and emit events.
        balances[msg.sender] -= numTokens;
        balances[receiver] += tokensToTransfer;
        if(tax > 0) {
            balances[owner()] += tax;
            emit Transfer(msg.sender, owner(), tax);
        }

        emit Transfer(msg.sender, receiver, tokensToTransfer);
        return true;
    }

    // Approve another address to spend tokens on your behalf.
    function approve(address spender, uint256 numTokens) public override returns (bool) {
        allowed[msg.sender][spender] = numTokens;
        emit Approval(msg.sender, spender, numTokens);
        return true;
    }

    // Check the amount of tokens that an owner allowed a spender.
    function allowance(address owner, address spender) public view override returns (uint256) {
        return allowed[owner][spender];
    }

    // Transfer tokens from one address to another, applying tax if applicable.
    function transferFrom(address sender, address recipient, uint256 numTokens) public override returns (bool) {
        require(numTokens <= balances[sender], "Insufficient balance");
        require(numTokens <= allowed[sender][msg.sender], "Insufficient allowance");
        require(numTokens <= maxTransactionAmount, "Exceeds max transaction amount");

        // Calculate and apply tax if not exempt.
        uint256 tax = taxExempt[sender] ? 0 : (numTokens * taxRate) / 100;
        uint256 tokensToTransfer = numTokens - tax;

        // Update balances, allowances, and emit events.
        balances[sender] -= numTokens;
        allowed[sender][msg.sender] -= numTokens;
        balances[recipient] += tokensToTransfer;
        if(tax > 0) {
            balances[owner()] += tax;
            emit Transfer(sender, owner(), tax);
        }

        emit Transfer(sender, recipient, tokensToTransfer);
        return true;
    }

    // Adjust the tax rate for transactions.
    function adjustTaxRate(uint256 newRate) public onlyOwner {
        taxRate = newRate;
    }

    // Adjust the maximum transaction amount.
    function adjustMaxTransactionAmount(uint256 newMax) public onlyOwner {
        maxTransactionAmount = newMax;
    }

    // Exempt or include an address in the taxation logic.
    function exemptAddressFromTax(address account, bool isExempt) public onlyOwner {
        taxExempt[account] = isExempt;
    }
}