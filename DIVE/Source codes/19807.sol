// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed _owner,
        address indexed spender,
        uint256 value
    );
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }

    function _contextSuffixLength() internal view virtual returns (uint256) {
        return 0;
    }
}

abstract contract Ownable is Context {
    address private _owner;
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(initialOwner);
    }

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        if (owner() != _msgSender()) {
            revert OwnableUnauthorizedAccount(_msgSender());
        }
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

contract Sale is Ownable {
    uint256 saleStartTime;
    uint256 saleEndTime;
    uint256 tier1Price = 0.00000068 ether;
    uint256 tier2Price = 0.000001 ether;
    uint256 tier3Price = 0.0000014 ether;
    uint256 tier4Price = 0.0000017 ether;
    uint256 tier5Price = 0.0000021 ether;
    bool saleStart;
    uint256 totalsoldToken;
    IERC20 tokenAddress;

    // withdraw
    address[] owners;
    mapping(address => bool) isOwner;
    uint256 signaturesRequired;
    mapping(address => mapping(uint => bool)) signatures;
    mapping(uint => bool) executed;
    mapping(uint256 => uint256) withdrawAmount;
    mapping(uint256 => address) withdrawUser;
    uint256 transactionCount;
    event Deposit(address indexed sender, uint value);
    event SubmitTransaction(
        address indexed owner,
        uint indexed txIndex,
        address indexed to,
        uint value
    );
    event ApproveTransaction(address indexed owner, uint indexed txIndex);
    event ExecuteTransaction(address indexed owner, uint indexed txIndex);

    modifier onlyApprover() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }

    struct user {
        uint256 tokenAmount;
        uint256 investAmount;
        uint256 buyTime;
    }
    mapping(address => user) userinfo;

    constructor(
        IERC20 _tokenAddress,
        address[] memory _owners,
        uint _signaturesRequired
    ) Ownable(msg.sender) {
        tokenAddress = _tokenAddress;
        require(_owners.length > 0, "Owners required");
        require(
            _signaturesRequired > 0 && _signaturesRequired <= _owners.length,
            "Invalid number of signatures required"
        );
        for (uint i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");
            isOwner[owner] = true;
            owners.push(owner);
        }
        signaturesRequired = _signaturesRequired;
    }

    function initializeSale(
        uint256 tokenAmount,
        uint256 _saleStartTime,
        uint256 _saleEndTime
    ) public onlyOwner {
        saleStartTime = _saleStartTime;
        saleEndTime = _saleEndTime;
        tokenAddress.transferFrom(msg.sender, address(this), tokenAmount);
        totalsoldToken = 0;
        saleStart = true;
    }

    function buy() public payable {
        require(saleStart == true, "sale not start");
        require(saleStartTime < block.timestamp, "sale is not start yet");
        require(saleEndTime >= block.timestamp, "sale time out");
        uint256 tokenAmount = calculateToken(msg.value);
        tokenAmount = tokenAmount * 10 ** tokenAddress.decimals();
        tokenAddress.transfer(msg.sender, tokenAmount);
        payable(address(this)).transfer(msg.value);
        userinfo[msg.sender].tokenAmount = tokenAmount;
        userinfo[msg.sender].investAmount = msg.value;
        userinfo[msg.sender].buyTime = block.timestamp;
        totalsoldToken = totalsoldToken + tokenAmount;
    }

    function calculateToken(uint256 _price) public view returns (uint256) {
        uint256 amount;
        if (
            totalsoldToken > 75000000000000000000000000  &&
            totalsoldToken <= 100000000000000000000000000
        ) {
            amount = _price / tier5Price;
        }
        if (
            totalsoldToken > 50000000000000000000000000 &&
            totalsoldToken <= 75000000000000000000000000
        ) {
            amount = _price / tier4Price;
        }
        if (
            totalsoldToken > 30000000000000000000000000 &&
            totalsoldToken <= 50000000000000000000000000
        ) {
            amount = _price / tier3Price;
        }
        if (
            totalsoldToken > 10000000000000000000000000 &&
            totalsoldToken <= 20000000000000000000000000
        ) {
            amount = _price / tier2Price;
        }
        if (totalsoldToken <= 10000000000000000000000000) {
            amount = _price / tier1Price;
        }
        return amount;
    }

    function getStartTime() public view returns (uint256) {
        return saleStartTime;
    }

    function getEndTime() public view returns (uint256) {
        return saleEndTime;
    }

    function getTier1Price() public view returns (uint256) {
        return tier1Price;
    }

    function getTier2Price() public view returns (uint256) {
        return tier2Price;
    }

    function getTier3Price() public view returns (uint256) {
        return tier3Price;
    }

    function getTier4Price() public view returns (uint256) {
        return tier4Price;
    }

    function getTier5Price() public view returns (uint256) {
        return tier5Price;
    }

    function getTotalSoldToken() public view returns (uint256) {
        return totalsoldToken;
    }

    function closeSale() public onlyOwner {
        saleStart = false;
    }

    function submitWithdraw(address to, uint value) public onlyApprover {
        uint txIndex = transactionCount;
        signatures[msg.sender][txIndex] = true;
        withdrawAmount[transactionCount] = value;
        withdrawUser[transactionCount] = to;
        emit SubmitTransaction(msg.sender, txIndex, to, value);
        transactionCount++;
    }

    function executeWithdraw(uint txIndex) public onlyApprover {
        require(txIndex < transactionCount, "Invalid transaction index");
        require(!executed[txIndex], "Transaction already executed");
        uint approvalCount = 0;
        for (uint i = 0; i < owners.length; i++) {
            if (signatures[owners[i]][txIndex]) {
                approvalCount++;
            }
        }
        require(approvalCount >= signaturesRequired, "Not enough approvals");
        executed[txIndex] = true;
        address _user = withdrawUser[txIndex];
        uint256 amount = withdrawAmount[txIndex];
        payable(_user).transfer(amount);
        emit ExecuteTransaction(msg.sender, txIndex);
    }

    function approveTransaction(uint txIndex) public onlyApprover {
        require(txIndex < transactionCount, "Invalid transaction index");
        require(signatures[msg.sender][txIndex] == false, "already approved");
        signatures[msg.sender][txIndex] = true;
        emit ApproveTransaction(msg.sender, txIndex);
    }

    function getTransaction(
        uint txIndex
    ) public view returns (address to, uint value) {
        require(txIndex < transactionCount, "Invalid transaction index");
        for (uint i = 0; i < owners.length; i++) {
            if (signatures[owners[i]][txIndex]) {
                return (owners[i], txIndex);
            }
        }
    }

    function getUserDetail(
        address _user
    )
        public
        view
        returns (uint256 tokenAmount, uint256 investAmount, uint256 buyTime)
    {
        return (
            userinfo[_user].tokenAmount,
            userinfo[_user].investAmount,
            userinfo[_user].buyTime
        );
    }
    function updateTierValue(uint256 _tier1Price ,
    uint256 _tier2Price ,
    uint256 _tier3Price ,
    uint256 _tier4Price ,
    uint256 _tier5Price )public onlyApprover {
        tier1Price = _tier1Price ;
        tier2Price = _tier2Price;
        tier3Price = _tier3Price;
        tier4Price = _tier4Price;
        tier5Price = _tier5Price;
    }

    receive() external payable {}
}