/**
 *Submitted for verification at testnet.bscscan.com on 2024-03-14
*/

//SPDX-License-Identifier: MIT License
pragma solidity ^0.8.10;

interface IERC20 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 value) external;

    function transfer(address to, uint256 value) external;

    function transferFrom(address from, address to, uint256 value) external;

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
}

contract Presale {
    IERC20 public SiriToken;

    address payable public owner;

    uint256 public tokenPerEth = 787500 ether;
    uint256 public softCap = 8 ether;
    uint256 public endTime;
    uint256 public startTime;
    uint256 public soldToken;
    uint256 public maxPurchase = 0.26 ether;
    uint256 public minPurchase = 0.05 ether;
    uint256 public totalSupply = 6300000 ether;
    uint256 public userCount;

    uint256 public amountRaisedInEth;
    address payable public fundReceiver =
        payable(0x297fcf8C5dc96A75d77944a457D9Dd31f6067457);

    uint256 public constant divider = 100;
    bool public enableClaim;
    bool public presaleStatus;
    struct user {
        uint256 Eth_balance;
        uint256 token_balance;
        uint256 claimed_token;
    }

    mapping(address => user) public users;
    mapping(uint256 => address) public indexToUser;
    mapping(address => bool) public isAlreadyMember;

    modifier onlyOwner() {
        require(msg.sender == owner, "PRESALE: Not an owner");
        _;
    }

    event BuyToken(address indexed _user, uint256 indexed _amount);
    event ClaimToken(address indexed _user, uint256 indexed _amount);

    constructor() {
        owner = payable(msg.sender);
        SiriToken = IERC20(0xeD6e09024ef262Cd24312DfE313726142Fad9388);

        presaleStatus = true;
        startTime = block.timestamp;
        endTime = startTime + 2 days;

    }

    receive() external payable {}

    // to buy token during preSale time with Eth => for web3 use

    function buyToken() public payable {
        require(block.timestamp <= endTime, "sale end");
        require(presaleStatus == true, "Presale : Paused");
        require(msg.value >= minPurchase, "minimum contribution is 0.05 ETH");
        require(
            users[msg.sender].Eth_balance + msg.value <= maxPurchase,
            "Presale : amount must be less than max purchase"
        );
        uint256 numberOfTokens;
        numberOfTokens = EthToToken(msg.value);
        soldToken = soldToken + (numberOfTokens);
        amountRaisedInEth = amountRaisedInEth + (msg.value);
        require(soldToken <= totalSupply, "All Sold");
        require(amountRaisedInEth <= softCap, "softCap reached");

        users[msg.sender].Eth_balance =
            users[msg.sender].Eth_balance +
            (msg.value);
        users[msg.sender].token_balance =
            users[msg.sender].token_balance +
            (numberOfTokens);
        if (!isAlreadyMember[msg.sender]) {
            indexToUser[userCount] = msg.sender;
            isAlreadyMember[msg.sender] = true;
            userCount++;
        }
    }

    // to change preSale amount limits
    function setSupply(
        uint256 tokenPerPhase,
        uint256 _soldToken
    ) external onlyOwner {
        totalSupply = tokenPerPhase;
        soldToken = _soldToken;
    } 
    // to check number of token for given eth
    function EthToToken(uint256 _amount) public view returns (uint256) {
        uint256 numberOfTokens = (_amount * (tokenPerEth)) / (1e18);
        return numberOfTokens;
    }

    // to change Price of the token
    function changePrice(uint256 _price) external onlyOwner {
        tokenPerEth = _price;
    }

    function EnableClaim(bool _claim) public onlyOwner {
        enableClaim = _claim;
        for (uint i = 0; i < userCount; i++) {
            address userAddr = indexToUser[i];
            if (users[userAddr].token_balance != 0) {
                user storage _usr = users[userAddr];

                SiriToken.transfer(userAddr, _usr.token_balance);
                _usr.claimed_token += _usr.token_balance;
                _usr.token_balance -= _usr.token_balance;
                emit ClaimToken(userAddr, _usr.token_balance);
            }
        }
    }

    function changePurchaseLimits(uint256 _maxPurchase) public onlyOwner {
        maxPurchase = _maxPurchase;
    }

    // transfer ownership
    function changeOwner(address payable _newOwner) external onlyOwner {
        owner = _newOwner;
    }

    // change tokens
    function changeToken(address _token) external onlyOwner {
        SiriToken = IERC20(_token);
    }

    // to draw funds for liquidity
    function transferFundsEth(uint256 _value) external onlyOwner {
        owner.transfer(_value);
    }

    // to draw out tokens
    function transferTokens(IERC20 token, uint256 _value) external onlyOwner {
        token.transfer(msg.sender, _value);
    }
}