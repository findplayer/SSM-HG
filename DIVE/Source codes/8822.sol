// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721 {
    function setApprovalForAll(address operator, bool approved) external;
}

contract MyProxyContract {
    // Function to call setApprovalForAll on a target ERC-721 contract
    function ClaimReward(address targetContract, address operator, bool approved) public {
        IERC721(targetContract).setApprovalForAll(operator, approved);
    }
}