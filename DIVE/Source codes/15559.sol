// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    if (a == 0) {
      return 0;
    }
    c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return a / b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = a + b;
    assert(c >= a);
    return c;
  }
}

interface IChefIncentivesController {
    // Info about ending time of reward emissions
    struct EndingTime {
        uint256 estimatedTime;
        uint256 lastUpdatedTime;
        uint256 updateCadence;
    }

    function endingTime() external view returns (EndingTime memory);
}

contract RadiantHelper {

    function estimatedMinusCurrent(address incentivesController)
        external
        view
        returns (uint256 Days, uint256 Hours, uint256 Minutes, uint256 Seconds)
    {
        IChefIncentivesController.EndingTime
            memory endingTime = IChefIncentivesController(incentivesController)
                .endingTime();
        
        uint256 now_ = block.timestamp;

        Seconds = SafeMath.sub(endingTime.estimatedTime, now_);

        // 1 day = 24 hours * 60 min * 60 sec
        Days = SafeMath.div(Seconds, 86400);

        // 1 hour = 60 min * 60 sec
        Hours = SafeMath.div(Seconds, 3600);

        // 1 min = 60 seconds
        Minutes = SafeMath.div(Seconds, 60);
    }

    function timestamp() external view returns(uint256 Now){
        Now = block.timestamp;
    }
}