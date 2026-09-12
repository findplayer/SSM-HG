// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, 'SafeMath: addition overflow');
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, 'SafeMath: subtraction overflow');
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, 'SafeMath: multiplication overflow');
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, 'SafeMath: division by zero');
        uint256 c = a / b;
        return c;
    }
}

contract BYFCOIN {
    using SafeMath for uint256;

    string public constant name = "BYFCOIN";
    string public constant symbol = "BYF";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    uint256 public maxSupply;
    uint256 public maxWalletBalance;
    uint256 public taxRate = 3; // 3% tax rate represented as a decimal fraction
    uint256 public lockTimeBlocks; // Lock duration in blocks
    uint256 public rate; // Rate of swap (BYF per ETH)

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;
    mapping(address => uint256) private unlockTime;
    mapping(address => bool) private mutex; // Mutex lock

    address payable public owner;
    address public tradingAddress;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Received(address indexed from, uint256 value);
    event Withdraw(address indexed to, uint256 value);
    event RateUpdated(uint256 newRate);
    event Bought(address indexed buyer, uint256 byfAmount, uint256 ethAmount);
    event Sold(address indexed seller, uint256 byfAmount, uint256 ethAmount);
    event TaxDeducted(address indexed from, address indexed to, uint256 value); // Added event for tax deduction

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }

    constructor() {
        owner = payable(msg.sender); // Set the owner to the address that deploys the contract
        totalSupply = 1000000000 * 10 ** uint256(decimals);
        maxSupply = totalSupply;
        maxWalletBalance = 20000 * 10 ** uint256(decimals);
        lockTimeBlocks = 105120000; // Equivalent to approximately 2 years with 15 seconds per block
        rate = 100000; // Initial rate: 100000 BYF per 1 ETH

        balances[msg.sender] = totalSupply;

        // Lock a portion of the owner's wallet balance for 2 years
        uint256 lockedBalance = 100000000 * 10 ** uint256(decimals);
        _lockTokens(msg.sender, lockedBalance, lockTimeBlocks);

        // Allocate 100,000,000 BYF for trading
        tradingAddress = address(this);
        balances[tradingAddress] = 100000000 * 10 ** uint256(decimals);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        _transfer(from, to, value);
        uint256 currentAllowance = allowances[from][msg.sender];
        require(currentAllowance >= value, "Transfer amount exceeds allowance");
        allowances[from][msg.sender] = currentAllowance.sub(value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowances[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        allowances[msg.sender][spender] = allowances[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, allowances[msg.sender][spender]);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        uint256 currentAllowance = allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "Decreased allowance below zero");
        allowances[msg.sender][spender] = currentAllowance.sub(subtractedValue);
        emit Approval(msg.sender, spender, allowances[msg.sender][spender]);
        return true;
    }

    function withdrawTokens(uint256 amount) external onlyOwner {
        _transfer(tradingAddress, msg.sender, amount);
    }

    function withdrawEther(uint256 amount) external onlyOwner {
        require(amount <= address(this).balance, "Insufficient contract balance");

        owner.transfer(amount); // Transfer the specified amount to the owner
        emit Withdraw(owner, amount); // Emit withdrawal event
    }

    function isUnlocked(address account) external view returns (bool) {
        return unlockTime[account] <= block.timestamp;
    }

    // Fallback function to receive Ether
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // Internal transfer function
    function _transfer(address from, address to, uint256 value) private {
        // Implement mutex lock at the beginning of the function
        require(!mutex[from], "Transfer in progress");
        mutex[from] = true;

        require(to != address(0), "Invalid address");
        require(value > 0, "Transfer value must be greater than zero");
        require(balances[from] >= value, "Insufficient balance");

        // Calculate the tax amount based on the tax rate
        uint256 taxAmount = (value.mul(taxRate)).div(100);

        // Deduct tax from transfer amount
        uint256 transferAmount = value.sub(taxAmount);

        if (from != owner && to != owner && balances[to].add(transferAmount) > maxWalletBalance) {
            uint256 excessTokens = balances[to].add(transferAmount).sub(maxWalletBalance);
            _lockTokens(to, excessTokens, lockTimeBlocks);
            transferAmount = transferAmount.sub(excessTokens);
        }

        balances[from] = balances[from].sub(value);
        balances[to] = balances[to].add(transferAmount);

        if (taxAmount > 0) {
            // Convert tax amount to ETH
            uint256 ethTaxAmount = _calculateEthAmount(taxAmount);
            // Transfer ETH tax to owner's wallet
            owner.transfer(ethTaxAmount);
            emit Transfer(from, owner, taxAmount);
            emit TaxDeducted(from, owner, ethTaxAmount); // Emit tax deduction event
        }

        emit Transfer(from, to, transferAmount);

        // Clear mutex lock at the end of the function
        mutex[from] = false;
    }

    // Function to calculate ETH amount equivalent to given BYF amount
    function _calculateEthAmount(uint256 byfAmount) private view returns (uint256) {
        require(rate > 0, "Rate must be greater than zero");
        // Calculate ETH amount based on current rate
        uint256 ethAmount = byfAmount.div(rate);
        return ethAmount;
    }

    // Lock tokens for the specified duration using a timestamp
    function _lockTokens(address account, uint256 amount, uint256 lockDuration) private {
        require(account != address(0), "Invalid address");
        require(lockDuration > 0, "Lock duration must be greater than zero");

        // Calculate the unlock timestamp based on the current block timestamp and the lock duration
        uint256 unlockTimestamp = block.timestamp + lockDuration;

        unlockTime[account] = unlockTimestamp;
        balances[account] = balances[account].sub(amount);
        emit Transfer(account, address(0), amount); // Event emitted after state change
    }

    function buyBYF(uint256 ethAmountInWei) external payable {
        require(ethAmountInWei > 0, "ETH amount must be greater than zero");

        // Implement mutex lock at the beginning of the function
        require(!mutex[msg.sender], "Buy in progress");
        mutex[msg.sender] = true;

        // Calculate the amount of BYF tokens to be bought based on the provided ETH amount and the current rate
        uint256 byfAmount = ethAmountInWei.mul(rate); // Convert from wei to BYF

        // Ensure that the contract has enough BYF tokens to fulfill the purchase
        require(balances[tradingAddress] >= byfAmount, "Insufficient BYF balance");

        // Transfer BYF tokens to the buyer
        balances[msg.sender] = balances[msg.sender].add(byfAmount);
        balances[tradingAddress] = balances[tradingAddress].sub(byfAmount);

        // Emit the Bought event
        emit Bought(msg.sender, byfAmount, ethAmountInWei);

        // Update the rate
        _updateRate(true);

        // Clear mutex lock at the end of the function
        mutex[msg.sender] = false;
    }

    // Function to sell BYF tokens for ETH
    function sellBYF(uint256 byfAmount) external {
        require(byfAmount > 0, "BYF amount must be greater than zero");
        require(balances[msg.sender] >= byfAmount, "Insufficient BYF balance");

        // Implement mutex lock at the beginning of the function
        require(!mutex[msg.sender], "Sell in progress");
        mutex[msg.sender] = true;

        // Calculate the amount of ETH to be received based on the current rate
        uint256 ethAmount = byfAmount.div(rate);

        // Transfer BYF tokens from the seller
        balances[msg.sender] = balances[msg.sender].sub(byfAmount);

        // Transfer ETH to the seller
        payable(msg.sender).transfer(ethAmount);

        // Emit the Sold event
        emit Sold(msg.sender, byfAmount, ethAmount);

        // Update the rate
        _updateRate(false);

        // Clear mutex lock at the end of the function
        mutex[msg.sender] = false;
    }

    // Internal function to update the rate
    function _updateRate(bool isBuy) private {
        if (isBuy) {
            // Decrease rate by 0.4% after each buy
            rate = rate.mul(996).div(1000);
        } else {
            // Increase rate by 0.1% after each sell
            rate = rate.mul(1001).div(1000);
        }

        // Emit the RateUpdated event with the new rate
        emit RateUpdated(rate);
    }
}