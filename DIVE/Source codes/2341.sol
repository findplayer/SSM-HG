// https://twitter.com/OHM_ERC404
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Governance {
    struct Proposal {
        uint256 id;
        string description;
        uint256 voteCount;
        mapping(address => bool) voted;
    }

    uint256 public nextProposalId = 1;
    mapping(uint256 => Proposal) public proposals;

    function createProposal(string memory description) external {
        uint256 proposalId = nextProposalId;
       
        nextProposalId++;
    }

    function vote(uint256 proposalId, uint256 nftId) external {
        Proposal storage proposal = proposals[proposalId];
        require(!proposal.voted[msg.sender], "Already voted");
        proposal.voteCount += 1;
        proposal.voted[msg.sender] = true;
    }
}