// SPDX-License-Identifier: MIT
/**
 * @notice Smart Contract developed by "t.me/frankfourier"
 * @dev The following contract is provided as-is per the specifications of the commissioner.
 * The smart contract developer does not endorse any of the included logic or functionality.
 * Potential investors should fully understand the risks and ensure compliance with their local regulations before participating.
 */

pragma solidity 0.8.20;
pragma abicoder v2;

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

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

contract Ryoshib is Ownable {
    /// @notice EIP-20 token name for this token
    string public constant name = "Ryoshibswap";

    /// @notice EIP-20 token symbol for this token
    string public constant symbol = "ROI";

    /// @notice EIP-20 token decimals for this token
    uint8 public constant decimals = 18;

    /// @notice Total number of tokens in circulation
    uint public totalSupply = 1_000_000_000e18; // 1 billion Roi

    /// @notice Address of the external wallet to store the tax
    address public externalTaxWallet;

    /// @notice Fixed Tax rate (3%)
    uint8 public taxRate = 50;

    uint256 public launchBlock = 0;

    /// @notice Allowance amounts on behalf of others
    mapping(address => mapping(address => uint)) internal allowances;

    /// @notice Official record of token balances for each account
    mapping(address => uint) internal balances;

    /// @notice A record of each accounts delegate
    mapping(address => address) public delegates;

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint) public numCheckpoints;

    /// @notice Mapping to keep track of LP pairs and their tax status
    mapping(address => bool) public lpPairs;

    mapping(address => bool) public whitelisted;

    struct Checkpoint {
        uint fromBlock;
        uint votes;
    }

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice The EIP-712 typehash for the permit struct used by the contract
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint previousBalance,
        uint newBalance
    );

    /// @notice The standard EIP-20 transfer event
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice The standard EIP-20 approval event
    event Approval(
        address indexed owner,
        address indexed spender,
        uint amount
    );

    /// @notice Event to log when a tax is collected
    event TaxCollected(
        address indexed sender,
        address indexed lpPair,
        uint amount
    );

    /**
     * @notice Construct a new Ryoshib token
     * @param _externalTaxWallet The initial account to grant fees
     */
    constructor(address _externalTaxWallet) Ownable(_externalTaxWallet) {
        balances[_externalTaxWallet] = uint(totalSupply);
        externalTaxWallet = _externalTaxWallet;
        _moveDelegates(address(0), delegates[_externalTaxWallet], totalSupply);
        emit Transfer(address(0), _externalTaxWallet, totalSupply);
    }

    /**
     * @notice Get the number of tokens `spender` is approved to spend on behalf of `account`
     * @param account The address of the account holding the funds
     * @param spender The address of the account spending the funds
     * @return The number of tokens approved
     */
    function allowance(
        address account,
        address spender
    ) external view returns (uint) {
        return allowances[account][spender];
    }

    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

    function setWhitelist(address account, bool state) external onlyOwner {
        whitelisted[account] = state;
    }

    function launch() external onlyOwner {
        require(launchBlock == 0, "Already launched");
        launchBlock = block.number;
    }

    function enableFees(bool state) external onlyOwner {
        if (taxRate != 0 && state == false)
        taxRate = 0;
        else if (taxRate == 0 && state == true)
        taxRate = 1;
        else 
        revert("Nothing to change");
    }

    // Function to add an LP pair for taxation
    function addLpPair(address lpPair) external onlyOwner {
        require(
            msg.sender == externalTaxWallet,
            "Ryoshib::addLpPair: only the admin can add LP pairs"
        );

        // Check if the address is a contract
        require(isContract(lpPair), "Ryoshib::addLpPair: address is not a contract");

        // Check if it's a Ryoshibswap V2 pair by attempting to call getReserves
        (bool success, ) = lpPair.call(
            abi.encodeWithSignature("getReserves()")
        );
        require(success, "Ryoshib::addLpPair: not a Ryoshibswap V2 pair contract");

        // Add the LP pair
        lpPairs[lpPair] = true;
    }

    // Function to remove an LP pair from taxation
    function removeLpPair(address lpPair) external onlyOwner {
        require(
            msg.sender == externalTaxWallet,
            "Ryoshib::removeLpPair: only the admin can remove LP pairs"
        );
        lpPairs[lpPair] = false;
    }

    // Function to change the external tax wallet address
    function changeExternalTaxWallet(address newWallet) external onlyOwner {
        require(
            msg.sender == externalTaxWallet,
            "Ryoshib::changeExternalTaxWallet: only the admin can change the external tax wallet"
        );
        externalTaxWallet = newWallet;
    }

    function moreThanFiveMinutesPassed() public view returns (bool) {
        // Assuming a block time of approximately 13 seconds
        // Adjust the block count as per the network's average block time
        if (launchBlock != 0) {
        uint256 blocksPassedSinceLaunch = block.number - launchBlock;
        uint256 fiveMinutesBlocks = 23;

        return blocksPassedSinceLaunch > fiveMinutesBlocks;
        } else return false;
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens approved
     * @return Whether or not the approval succeeded
     */
    function approve(address spender, uint amount) external returns (bool) {
        allowances[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transferFrom(
        address src,
        address dst,
        uint amount
    ) external returns (bool) {
        address spender = msg.sender;
        uint spenderAllowance = allowances[src][spender];

        if (spender != src && spenderAllowance != type(uint).max) {
            uint newAllowance =
                spenderAllowance - amount;
            allowances[src][spender] = newAllowance;

            emit Approval(src, spender, newAllowance);
        }

        _transferTokens(src, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return Whether or not the transfer succeeded
     */
    function transfer(address dst, uint amount) external returns (bool) {
        _transferTokens(msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Get the current voting power of a user
     * @param user The address of the user
     * @return The current voting power of the user
     */
    function getCurrentVotes(address user) external view returns (uint) {
        uint nCheckpoints = numCheckpoints[user];
        return nCheckpoints > 0 ? checkpoints[user][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Get the number of tokens held by the `account`
     * @param account The address of the account to get the balance of
     * @return The number of tokens held
     */
    function balanceOf(address account) external view returns (uint) {
        return balances[account];
    }

    /**
     * @notice Get the amount of voting power a user had at a specific block
     * @param user The address of the user
     * @param blockNumber The block number to get the voting power at
     * @return The voting power the user had at the specified block
     */
    function getPriorVotes(address user, uint blockNumber) external view returns (uint) {
        require(
            blockNumber < block.number,
            "Ryoshib::getPriorVotes: not yet determined"
        );

        uint nCheckpoints = numCheckpoints[user];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent checkpoint
        if (checkpoints[user][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[user][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[user][0].fromBlock > blockNumber) {
            return 0;
        }

        // Binary search to get the desired checkpoint
        uint lower = 0;
        uint upper = nCheckpoints - 1;
        while (upper > lower) {
            uint center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory checkpoint = checkpoints[user][center];
            if (checkpoint.fromBlock == blockNumber) {
                return checkpoint.votes;
            } else if (checkpoint.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[user][lower].votes;
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required by the EIP712 signature
     * @param expiry The contract state required by the EIP712 signature
     * @param v The contract state required by the EIP712 signature
     * @param r The contract state required by the EIP712 signature
     * @param s The contract state required by the EIP712 signature
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(expiry == 0 || block.timestamp <= expiry, "Ryoshib::delegateBySig: signature expired");
        require(nonce == nonces[msg.sender]++, "Ryoshib::delegateBySig: invalid nonce");
        require(delegatee == address(0) || delegatee == msg.sender, "Ryoshib::delegateBySig: invalid delegatee");

        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name)),
                block.chainid,
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Ryoshib::delegateBySig: invalid signature");
        require(signatory == msg.sender, "Ryoshib::delegateBySig: unauthorized");
        
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Change delegation for `delegator` to `delegatee` by
     * transferring its vote power.
     * @param delegator The address that is delegating its vote power
     * @param delegatee The address to delegate the vote power to
     */
    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint delegatorBalance = balances[delegator];

        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    /**
     * @notice Move voting power `_amount` from `srcDelegatee` to `dstDelegatee`
     * @param srcDelegatee The source delegatee
     * @param dstDelegatee The destination delegatee
     * @param amount The amount of voting power to move
     */
    function _moveDelegates(address srcDelegatee, address dstDelegatee, uint amount) internal {
        if (srcDelegatee != dstDelegatee && amount > 0) {
            if (srcDelegatee != address(0)) {
                uint srcRep = numCheckpoints[srcDelegatee];
                uint srcRepOld = srcRep > 0 ? checkpoints[srcDelegatee][srcRep - 1].votes : 0;
                uint srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcDelegatee, srcRep, srcRepOld, srcRepNew);
            }

            if (dstDelegatee != address(0)) {
                uint dstRep = numCheckpoints[dstDelegatee];
                uint dstRepOld = dstRep > 0 ? checkpoints[dstDelegatee][dstRep - 1].votes : 0;
                uint dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstDelegatee, dstRep, dstRepOld, dstRepNew);
            }
        }
    }

    // Function to check if a transfer transaction is coming from an LP pair
    function _isTransferFromLpPair(
        address sender,
        address recipient
    ) internal view returns (bool) {
        return recipient != owner() && !whitelisted[recipient] && lpPairs[sender] && !lpPairs[recipient];
    }

    // Function to check if a transfer transaction is directed to an LP pair
    function _isTransferToLpPair(
        address sender,
        address recipient
    ) internal view returns (bool) {
        return sender != owner() && !whitelisted[sender] && !lpPairs[sender] && lpPairs[recipient];
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`, with the caveat that
     * all the tokens must be transferred from the caller's balance.
     * @param src The source address
     * @param dst The destination address
     * @param amount The amount of tokens to send
     */
    function _transferTokens(address src, address dst, uint amount) internal {
        require(
            src != address(0),
            "Ryoshib::_transferTokens: cannot transfer from the zero address"
        );
        require(
            dst != address(0),
            "Ryoshib::_transferTokens: cannot transfer to the zero address"
        );

        if (taxRate == 50 && moreThanFiveMinutesPassed())
        taxRate = 1;

        if (taxRate != 0 && (_isTransferToLpPair(src, dst) || _isTransferFromLpPair(src, dst))) {
            // Handle tax for LP pair transfers
            uint taxAmount = (uint(amount) * uint(taxRate)) / 100;
            uint netAmount = amount - taxAmount;

            balances[src] -= amount;
            balances[dst] += netAmount;
            emit Transfer(src, dst, netAmount);

            // Move delegates
            _moveDelegates(delegates[src], delegates[dst], netAmount);

            // Transfer the tax amount to the external tax wallet
            balances[externalTaxWallet] += taxAmount;
            _moveDelegates(delegates[src], delegates[externalTaxWallet], taxAmount);

            emit Transfer(src, externalTaxWallet, taxAmount);
            emit TaxCollected(src, src, taxAmount);
        } else {
            balances[src] -= amount;
            balances[dst] += amount;
            emit Transfer(src, dst, amount);

            _moveDelegates(delegates[src], delegates[dst], amount);
        }
    }

    /**
     * @notice Write checkpoint for delegate `d` with `_votes`
     * @param d The address of the delegate
     * @param nCheckpoints The number of checkpoints
     * @param oldVotes The previous number of votes
     * @param newVotes The new number of votes
     */
    function _writeCheckpoint(address d, uint nCheckpoints, uint oldVotes, uint newVotes) internal {
        uint blockNumber = block.number;

        if (nCheckpoints > 0 && checkpoints[d][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[d][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[d][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[d] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(d, oldVotes, newVotes);
    }
}