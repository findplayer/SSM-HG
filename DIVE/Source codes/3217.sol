// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract RevenueShare {
    address public owner;
    IERC20 public opmndToken;
    mapping(address => uint256) public holderSnapshots; // Stores OPMND balance snapshot for addresses
    uint256 public snapshotTotal; // Total OPMND in snapshot for eligible holders
    bool public claimActive = false;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address _tokenAddress) {
        owner = msg.sender;
        opmndToken = IERC20(_tokenAddress);
    }

    function changeOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function toggleClaimActive() external onlyOwner {
        claimActive = !claimActive;
    }

    function uploadSnapshot(address[] calldata addresses, uint256[] calldata balances) external onlyOwner {
        require(addresses.length == balances.length, "Array length mismatch");
        uint256 total = 0;
        for (uint i = 0; i < addresses.length; i++) {
            if (balances[i] >= 1000 * 10**18) { // Assuming OPMND has 18 decimals
                holderSnapshots[addresses[i]] = balances[i];
                total += balances[i];
            }
        }
        snapshotTotal = total;
    }

    function claimReward() external {
        require(claimActive, "Claiming not active");
        require(holderSnapshots[msg.sender] > 0, "No reward available");
        
        uint256 reward = address(this).balance * holderSnapshots[msg.sender] / snapshotTotal;
        payable(msg.sender).transfer(reward);
        
        // Reset holder's snapshot balance to prevent re-claiming
        snapshotTotal -= holderSnapshots[msg.sender];
        holderSnapshots[msg.sender] = 0;
    }

    function withdrawETH() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    // Fallback function to receive ETH
    receive() external payable {}
}