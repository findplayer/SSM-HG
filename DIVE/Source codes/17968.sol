// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract RegistrationContract {
    event Registration(address, uint8);

    struct Level {
        uint256 fee;
        uint256 reward;
    }

    mapping(uint8 => Level) public levels;
    mapping(bytes32 => address) public codeOwner;
    mapping(address => uint256) public promoterBalance;

    uint256 promoterFunds;
    uint256 public codeRegistrationFee;
    address payable private owner;

    constructor() {
        setLevel(0, 100000000000000000, 50000000000000000);
        setLevel(1, 300000000000000000, 150000000000000000);
        setLevel(2, 700000000000000000, 400000000000000000);
        setLevel(3, 2000000000000000000, 1000000000000000000);
        codeRegistrationFee = 5000000000000000;
        owner = payable(msg.sender);
    }

    function createCode(string calldata _code) public payable {
        bytes32 codeHash = keccak256(abi.encodePacked(_code));
        require(codeOwner[codeHash] == address(0), "Code already taken");
        if(msg.sender != owner) {
        require(
            msg.value >= codeRegistrationFee,
            "Not enough ether for registration fee"
        );
        }
        codeOwner[codeHash] = msg.sender;
    }

    function register(string calldata _code, uint8 _level) public payable {
        require(_level <= 3, "Viable levels: 0,1,2,3");
        Level storage level = levels[_level];
        if(msg.sender != owner) {
        require(
            msg.value >= level.fee,
            "Not enough ether for registration fee"
        ); }
        bytes32 codeHash = keccak256(abi.encodePacked(_code));
        address promoter = codeOwner[codeHash];
        if (promoter != address(0)) {
            promoterBalance[promoter] += level.reward;
            promoterFunds += level.reward;
        }
        emit Registration(msg.sender, _level);
    }

    function promoterWithdraw() public {
        uint256 tempBalance = promoterBalance[msg.sender];
        require(tempBalance > 0, "You have nothing to withdraw");
        promoterBalance[msg.sender] = 0;
        promoterFunds -= tempBalance;
        (bool success, ) = payable(msg.sender).call{value: tempBalance}("");
        require(success, "Transfer failed");
    }

    function withdraw() public onlyOwner {
        uint256 ownerBalance = address(this).balance - promoterFunds;
        (bool success, ) = owner.call{value: ownerBalance}("");
        require(success, "Transfer failed");
    }

    function setLevel(uint8 _level, uint256 _fee, uint256 _reward) private {
        levels[_level] = Level(_fee, _reward);
    }

    function adjustLevel(
        uint8 _level,
        uint256 _newFee,
        uint256 _newReward
    ) public onlyOwner {
        setLevel(_level, _newFee, _newReward);
    }

    function adjustCodeRegistrationFee(uint256 _newFee) public onlyOwner {
        codeRegistrationFee = _newFee;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "You are not the owner of the contract.");
        _;
    }
}