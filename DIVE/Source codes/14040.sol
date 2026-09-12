// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract InterestRate {
    uint256 public baseRatePerYear;
    uint256 public multiplierPerYear;
    uint256 public jumpMultiplierPerYear;
    uint256 public kink;

    constructor(uint256 baseRatePerYear_, uint256 multiplierPerYear_, uint256 jumpMultiplierPerYear_, uint256 kink_) {
        baseRatePerYear = baseRatePerYear_;
        multiplierPerYear = multiplierPerYear_;
        jumpMultiplierPerYear = jumpMultiplierPerYear_;
        kink = kink_;
    }

    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256) {
        if (borrows == 0) {
            return 0;
        }
        return borrows * 1e18 / (cash + borrows - reserves);
    }

    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        if (util <= kink) {
            return (util * multiplierPerYear / 1e18) + baseRatePerYear;
        } else {
            uint256 normalRate = (kink * multiplierPerYear / 1e18) + baseRatePerYear;
            uint256 excessUtil = util - kink;
            return (excessUtil * jumpMultiplierPerYear / 1e18) + normalRate;
        }
    }

    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactorMantissa) public view returns (uint256) {
        uint256 oneMinusReserveFactor = 1e18 - reserveFactorMantissa;
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = borrowRate * oneMinusReserveFactor / 1e18;
        return utilizationRate(cash, borrows, reserves) * rateToPool / 1e18;
    }

    function updateBaseRatePerYear(uint256 newBaseRatePerYear) external {
        baseRatePerYear = newBaseRatePerYear;
    }

    function updateMultiplierPerYear(uint256 newMultiplierPerYear) external {
        multiplierPerYear = newMultiplierPerYear;
    }

    function updateJumpMultiplierPerYear(uint256 newJumpMultiplierPerYear) external {
        jumpMultiplierPerYear = newJumpMultiplierPerYear;
    }

    function updateKink(uint256 newKink) external {
        kink = newKink;
    }
}