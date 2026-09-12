// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC721 {
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract LiquidationManager {
    struct Loan {
        uint256 amountBorrowed;
        uint256 collateralId;
        address borrower;
        uint256 loanStart;
        uint256 interestRate;
    }
    
    mapping(uint256 => Loan) public loans;
    address public admin;
    address public priceOracle;
    IERC20 public lendingToken;
    IERC721 public collateralToken;
    
    uint256 public constant LIQUIDATION_THRESHOLD = 110;
    uint256 public constant LIQUIDATION_PENALTY = 5; 

    event LoanLiquidated(uint256 loanId, address liquidator);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    constructor(address _priceOracle, address _lendingToken, address _collateralToken) {
        admin = msg.sender;
        priceOracle = _priceOracle;
        lendingToken = IERC20(_lendingToken);
        collateralToken = IERC721(_collateralToken);
    }

    function checkAndLiquidate(uint256 loanId) external {
        Loan storage loan = loans[loanId];
        uint256 loanValue = _calculateLoanValue(loan.amountBorrowed, loan.loanStart, loan.interestRate);
        uint256 collateralValue = _getCollateralValue(loan.collateralId);
        
        if (_isUnderCollateralized(loanValue, collateralValue)) {
            _liquidateLoan(loanId, loan);
            emit LoanLiquidated(loanId, msg.sender);
        }
    }

    function _calculateLoanValue(uint256 amountBorrowed, uint256 loanStart, uint256 interestRate) internal view returns (uint256) {
        uint256 timeElapsed = block.timestamp - loanStart;
        uint256 interestAccrued = amountBorrowed * interestRate * timeElapsed / (365 days) / 100;
        return amountBorrowed + interestAccrued;
    }

    function _getCollateralValue(uint256 collateralId) internal view returns (uint256) {
    
        return 0; //
    }

    function _isUnderCollateralized(uint256 loanValue, uint256 collateralValue) internal pure returns (bool) {
        uint256 ltv = loanValue * 100 / collateralValue;
        return ltv > LIQUIDATION_THRESHOLD;
    }

    function _liquidateLoan(uint256 loanId, Loan storage loan) internal {
        uint256 repaymentAmount = _calculateRepaymentAmount(loan.amountBorrowed);
        
        lendingToken.transferFrom(msg.sender, admin, repaymentAmount);
        collateralToken.transferFrom(address(this), msg.sender, loan.collateralId);
        
        delete loans[loanId];
    }
    
    function _calculateRepaymentAmount(uint256 amountBorrowed) internal pure returns (uint256) {
        return amountBorrowed + (amountBorrowed * LIQUIDATION_PENALTY / 100);
    }

    function updateAdmin(address newAdmin) external onlyAdmin {
        admin = newAdmin;
    }
}