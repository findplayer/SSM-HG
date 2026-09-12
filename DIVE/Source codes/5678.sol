// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ILendingToken {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface ICollateralToken {
    function ownerOf(uint256 tokenId) external view returns (address);
    function transferFrom(address from, address to, uint256 tokenId) external;
}

contract RepaymentManager {
    address public admin;
    ILendingToken public lendingToken;
    mapping(uint256 => uint256) public repayments;

    constructor(address _lendingToken) {
        admin = msg.sender;
        lendingToken = ILendingToken(_lendingToken);
    }

    function initiateRepayment(uint256 loanId, uint256 amount) external {
        require(lendingToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        repayments[loanId] += amount;
    }

    function finalizeRepayment(uint256 loanId, address borrower, uint256 totalAmount) external {
        require(msg.sender == admin, "Unauthorized");
        require(repayments[loanId] == totalAmount, "Incorrect repayment amount");
        lendingToken.transfer(borrower, repayments[loanId]);
        delete repayments[loanId];
    }

    function updateAdmin(address newAdmin) external {
        require(msg.sender == admin, "Unauthorized");
        admin = newAdmin;
    }
}

contract CollateralManager {
    address public admin;
    ICollateralToken public collateralToken;
    mapping(uint256 => address) public loanToCollateralOwner;

    constructor(address _collateralToken) {
        admin = msg.sender;
        collateralToken = ICollateralToken(_collateralToken);
    }

    function lockCollateral(uint256 loanId, uint256 collateralId, address borrower) external {
        require(msg.sender == admin, "Unauthorized");
        collateralToken.transferFrom(borrower, address(this), collateralId);
        loanToCollateralOwner[loanId] = borrower;
    }

    function unlockCollateral(uint256 loanId, uint256 collateralId) external {
        require(msg.sender == admin, "Unauthorized");
        address owner = loanToCollateralOwner[loanId];
        collateralToken.transferFrom(address(this), owner, collateralId);
        delete loanToCollateralOwner[loanId];
    }

    function updateAdmin(address newAdmin) external {
        require(msg.sender == admin, "Unauthorized");
        admin = newAdmin;
    }
}

contract Governance {
    address public admin;
    mapping(address => bool) public proposals;

    constructor() {
        admin = msg.sender;
    }

    function createProposal(address proposal) external {
        require(msg.sender == admin, "Unauthorized");
        proposals[proposal] = true;
    }

    function executeProposal(address proposal) external {
        require(proposals[proposal], "Invalid proposal");
        proposals[proposal] = false;
    }

    function updateAdmin(address newAdmin) external {
        require(msg.sender == admin, "Unauthorized");
        admin = newAdmin;
    }
}