// SPDX-License-Identifier: MIT

// ██╗  ██╗ █████╗ ██╗███████╗███████╗███╗   ██╗   ███████╗██╗███╗   ██╗ █████╗ ███╗   ██╗ ██████╗███████╗
// ██║ ██╔╝██╔══██╗██║╚══███╔╝██╔════╝████╗  ██║   ██╔════╝██║████╗  ██║██╔══██╗████╗  ██║██╔════╝██╔════╝
// █████╔╝ ███████║██║  ███╔╝ █████╗  ██╔██╗ ██║   █████╗  ██║██╔██╗ ██║███████║██╔██╗ ██║██║     █████╗
// ██╔═██╗ ██╔══██║██║ ███╔╝  ██╔══╝  ██║╚██╗██║   ██╔══╝  ██║██║╚██╗██║██╔══██║██║╚██╗██║██║     ██╔══╝
// ██║  ██╗██║  ██║██║███████╗███████╗██║ ╚████║██╗██║     ██║██║ ╚████║██║  ██║██║ ╚████║╚██████╗███████╗
// ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝╚═╝     ╚═╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═══╝ ╚═════╝╚══════╝

pragma solidity =0.8.9;

struct Vote {
    uint8 option;
    uint256 points;
}

contract VotingWithPredefinedPoints {
    uint8 public immutable minOption;
    uint8 public immutable maxOption;

    bytes32 public immutable merkleRootHash;
    uint256 public immutable merkleTreeHeight;

    uint256 public immutable startTimestamp;
    uint256 public immutable endTimestamp;

    mapping(uint8/*option*/ => uint256/*casted vote points*/) public castedVotePoints;
    mapping(address => Vote) public votes;

    constructor(
        uint8 _minOption,
        uint8 _maxOption,
        bytes32 _merkleRootHash,
        uint256 _merkleTreeHeight,
        uint256 _startTimestamp,
        uint256 _endTimestamp
    ) {
        minOption = _minOption;
        maxOption = _maxOption;

        merkleRootHash = _merkleRootHash;
        merkleTreeHeight = _merkleTreeHeight;

        startTimestamp = _startTimestamp;
        endTimestamp = _endTimestamp;
    }

    function castVote(uint8 _option, uint256 _votePoints, uint256 _index, bytes32[] calldata _merkleProof) external {
        require(_option >= minOption && _option <= maxOption, "Option out of range");
        require(_votePoints != 0, "Zero vote points");
        require(block.timestamp >= startTimestamp, "Voting not started yet");
        require(block.timestamp <= endTimestamp, "Voting already ended");
        require(verifyMerkleProof(msg.sender, _votePoints, _index, _merkleProof), "Merkle proof verification failed");

        require(votes[msg.sender].points == 0, "Already voted");
        votes[msg.sender] = Vote({option: _option, points: _votePoints});

        castedVotePoints[_option] += _votePoints;
    }

    function getVotePoints() external view returns (Vote[] memory) {
        Vote[] memory votePoints = new Vote[](maxOption - minOption + 1);

        for (uint8 i = minOption; i <= maxOption; ++i) {
            votePoints[i - minOption] = Vote({option: i, points: castedVotePoints[i]});
        }

        return votePoints;
    }

    function verifyMerkleProof(
        address _user,
        uint256 _votePoints,
        uint256 _index,
        bytes32[] calldata _merkleProof
    ) public view returns (bool) {
        if (_merkleProof.length != merkleTreeHeight) {
            return false;
        }

        uint256 path = _index;
        bytes32 nodeHash = keccak256(abi.encode(_index, _user, _votePoints));

        for (uint16 i = 0; i < _merkleProof.length; ++i) {
            if ((path & 0x01) == 0) {
                nodeHash = keccak256(abi.encode(nodeHash, _merkleProof[i]));
            } else {
                nodeHash = keccak256(abi.encode(_merkleProof[i], nodeHash));
            }
            path = path >> 1;
        }

        return nodeHash == merkleRootHash;
    }
}