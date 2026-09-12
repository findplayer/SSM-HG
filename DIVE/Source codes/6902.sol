// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/// Signed Integer Math
library IntSafeMath {
    /**
     * @dev Adds two signed numbers, throws on overflow.
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result = a + b, reverts on over/undeflow
     */
    function add(int256 a, int256 b) internal pure returns (int256 result) {
        unchecked {
            result = a + b;
        }

        // Case 1: both addends are positive
        if ((a > 0 && b > 0) && result < 0) {
            revert(
                "Int256SafeMath: Addition overflow positive (a + b) > type(int256).max"
            );
        }

        // Case 2: both addends are negative
        if ((a < 0 && b < 0) && result > 0) {
            revert(
                "Int256SafeMath: Addition underflow negative (a + b) < type(int256).min"
            );
        }
    }

    /**
     * @dev Signed integer division, truncating the quotient to integer.
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result = (a / b) | reverts on overflow
     */
    function div(int256 a, int256 b) internal pure returns (int256 result) {
        // |-2**255| * (-1) > |2**255 - 1|, thus overflow
        if (a == type(int256).min && b == -1) {
            revert("Int256SafeMath: Division overflow");
        }

        // if |a| < |b| then |a| / |b| == fraction, unsupported in int
        if (a == 0 || mod(a) < mod(b)) {
            result = 0;
            return result;
        }
        // No mathematical solution
        if (b == 0) revert("Int256SafeMath: Division by zero");

        // All other valid cases, fractions dropped
        unchecked {
            result = a / b;
        }
    }

    /**
     * @dev Verifies whether a == b;
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result ∈ {1, 0}
     */
    function equal(int256 a, int256 b) internal pure returns (int256 result) {
        result = a == b ? int256(1) : int256(0);
    }

    /**
     * @dev Verifies whether a > b;
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result ∈ {1, 0}
     */
    function greaterThan(int256 a, int256 b)
        internal
        pure
        returns (int256 result)
    {
        result = a > b ? int256(1) : int256(0);
    }

    /**
     * @dev Verifies whether a < b;
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result ∈ {1, 0}
     */
    function lessThan(int256 a, int256 b)
        internal
        pure
        returns (int256 result)
    {
        result = a < b ? int256(1) : int256(0);
    }

    /**
     * @dev Finds and returns the biggest of the two signed numbers
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result ∈ {a, b}
     */
    function maxInt256(int256 a, int256 b)
        internal
        pure
        returns (int256 result)
    {
        result = a >= b ? a : b;
    }

    /**
     * @dev Finds and returns the smallest of the two signed numbers
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result ∈ {a, b}
     */
    function minInt256(int256 a, int256 b)
        internal
        pure
        returns (int256 result)
    {
        result = a < b ? a : b;
    }

    /**
     * @dev Returns the module of the number `n`
     * @param n a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result = |n| or reverts if n == type(int256).min
     */
    function mod(int256 n) internal pure returns (int256 result) {
        if (n == type(int256).min) {
            revert("Int256SafeMath: Mod overflow");
        }
        if (n < 0) {
            result = n * (-1);
        } else {
            result = n;
        }
    }

    /**
     * @dev Multiplies two signed numbers, throws on overflow.
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result = a * b or reverts on over- underflow
     */
    function mul(int256 a, int256 b) internal pure returns (int256 result) {
        // Case 1: either or both factors eq zero
        if (a == 0 || b == 0) {
            result = 0;
            return result;
        }

        unchecked {
            result = a * b;
        }

        // Case 2: both factors are positive or both are negative
        if (((a > 0 && b > 0) || (a < 0 && b < 0)) && result < 0) {
            revert(
                "Int256SafeMath: Multiplication overflow, (a * b) > type(int256).max"
            );
        }

        // Case 3: one of the factors is positive, while another is negative
        if ((((a < 0 && b > 0) || (a > 0 && b < 0))) && result >= 0) {
            revert(
                "Int256SafeMath: Multiplication underflow, (a * b) < type(int256).min"
            );
        }
    }

    /**
     * @dev Verifies whether a != b;
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result ∈ {1, 0}
     */
    function notEqual(int256 a, int256 b)
        internal
        pure
        returns (int256 result)
    {
        result = a != b ? int256(1) : int256(0);
    }

    /**
     * @dev Subtracts two signed numbers, throws on underflow (i.e. if (a - b) < int256.min).
     * @param a a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @param b a valid signed integer ∈ {-2^255, ... 2^255-1}
     * @return result = a - b or reverts on underflow
     */
    function sub(int256 a, int256 b) internal pure returns (int256 result) {
        unchecked {
            result = a - b;
        }

        if ((a < -1 && b > 0) && result > a) {
            revert(
                "Int256SafeMath: Subtraction underflow, (a - b) < < type(int256).min"
            );
        }
    }
}

interface IController {
    // Info about ending time of reward emissions
    struct EndingTime {
        uint256 estimatedTime;
        uint256 lastUpdatedTime;
        uint256 updateCadence;
    }

    function endingTime() external view returns (EndingTime memory);
}

contract TimestampHelper {
    function estimatedMinusCurrent(address incentivesController)
        external
        view
        returns (
            int256 Days,
            int256 Hours,
            int256 Minutes,
            int256 Seconds
        )
    {
        IController.EndingTime
            memory endingTime = IController(incentivesController)
                .endingTime();

        int256 now_ = int256(block.timestamp);

        Seconds = IntSafeMath.sub(int256(endingTime.estimatedTime), now_);

        // 1 day = 24 hours * 60 min * 60 sec
        Days = IntSafeMath.div(Seconds, 86400);

        // 1 hour = 60 min * 60 sec
        Hours = IntSafeMath.div(Seconds, 3600);

        // 1 min = 60 seconds
        Minutes = IntSafeMath.div(Seconds, 60);
    }

    function currentTimestamp() external view returns (uint256 Now) {
        Now = block.timestamp;
    }
}