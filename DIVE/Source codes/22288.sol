pragma solidity 0.8.21;

contract MockOracle {
    uint256 public price;

    function getExchangeRate() external view returns (uint256 exchangeRate_) {
        return price;
    }

    function setPrice(uint256 price_) external {
        price = price_;
    }
}