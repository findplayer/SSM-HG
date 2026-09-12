// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    event OwnershipRenounced(address indexed previousOwner);

    constructor(address initialOwner) {
        if (initialOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _owner = initialOwner; // Assign ownership to initialOwner
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

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipRenounced(_owner);
        _owner = address(0);
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() private {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
    }

    function _nonReentrantAfter() private {
        _status = _NOT_ENTERED;
    }
}

contract RapiDex is IERC20, IERC20Metadata, Ownable, ReentrancyGuard {
    string public override name = "RapiDex";
    string public override symbol = "RDEX";
    uint8 public override decimals = 18;

    uint256 private constant BASE = 10;
    uint256 private constant INITIAL_SUPPLY = 2_000_000_000; // 2 billion tokens

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    uint256 public buyFeePercent = 5; // 5%
    uint256 public sellFeePercent = 5; // 5%
    uint256 public buyLimit = 20000000 * 10**uint(decimals);
    uint256 public sellLimit = 20000000 * 10**uint(decimals);
    address public dexPair;
    mapping(address => bool) public feeExempt;

    event DexPairSet(address indexed dexPair);
    event BuyFeePercentSet(uint256 buyFeePercent);
    event SellFeePercentSet(uint256 sellFeePercent);
    event BuyLimitSet(uint256 buyLimit);
    event SellLimitSet(uint256 sellLimit);
    event FeeExemptSet(address indexed account, bool isExempt);

    constructor() Ownable(msg.sender) {
        uint256 totalInitialSupply = INITIAL_SUPPLY * (BASE ** uint256(decimals));
        _mint(msg.sender, totalInitialSupply);

        feeExempt[msg.sender] = true;

        emit FeeExemptSet(msg.sender, true);
    }

    function setDexPair(address _dexPair) external onlyOwner {
        require(_dexPair != address(0), "Invalid address");
        dexPair = _dexPair;
        emit DexPairSet(_dexPair);
    }

    function setBuyFeePercent(uint256 _buyFeePercent) external onlyOwner {
        buyFeePercent = _buyFeePercent;
        emit BuyFeePercentSet(_buyFeePercent);
    }

    function setSellFeePercent(uint256 _sellFeePercent) external onlyOwner {
        sellFeePercent = _sellFeePercent;
        emit SellFeePercentSet(_sellFeePercent);
    }

    function setBuyLimit(uint256 _buyLimit) external onlyOwner {
        buyLimit = _buyLimit;
        emit BuyLimitSet(_buyLimit);
    }

    function setSellLimit(uint256 _sellLimit) external onlyOwner {
        sellLimit = _sellLimit;
        emit SellLimitSet(_sellLimit);
    }

    function setFeeExempt(address account, bool isExempt) external onlyOwner {
        feeExempt[account] = isExempt;
        emit FeeExemptSet(account, isExempt);
    }

    function transfer(address recipient, uint256 amount) public override nonReentrant returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override nonReentrant returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(recipient != address(0), "Invalid recipient address");

        uint256 feeAmount = 0;
        // Check for exemption from fees
        if (!feeExempt[sender] && !feeExempt[recipient]) {
            if (recipient == dexPair) {
                feeAmount = amount * sellFeePercent / 100;
            } else if (sender == dexPair) {
                feeAmount = amount * buyFeePercent / 100;
            }
        }

        uint256 amountAfterFee = amount - feeAmount;
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amountAfterFee;
        emit Transfer(sender, recipient, amountAfterFee);

        if (feeAmount > 0) {
            _balances[owner()] = _balances[owner()] + feeAmount;
            emit Transfer(sender, owner(), feeAmount);
        }
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
}