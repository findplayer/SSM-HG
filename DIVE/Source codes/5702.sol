// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        return c;
    }
}

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);
}

contract ArabianHorses is Context, IERC20, Ownable {
    using SafeMath for uint256;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public _isExcludedFromLock;

    /// @notice keep track of last buy Timestamp;
    mapping(address => uint256) public lastBuyTimestamp;
    uint256 public _buyCount = 0;

    uint8 private constant _decimals = 18;
    uint256 private _tTotal = 10_000_000_000 * 10**_decimals; //10 billion total supply
    uint256 public lockedSupply;
    uint256 public sellLockedTime;
    bool public lockEnabled = true;
    string private constant _name = "Arabian horses";
    string private constant _symbol = "ARBH";

    IUniswapV2Router02 private uniswapRouter;
    address private uniswapV2Pair;

    receive() external payable {}

    constructor() {
        lockedSupply = (_tTotal * 20) / 100; //20 perent supply will be locked
        uint256 ownerSupply = _tTotal - lockedSupply;
        _balances[_msgSender()] = ownerSupply;
        _balances[address(this)] = lockedSupply;
        _isExcludedFromLock[owner()] = true;
        _isExcludedFromLock[address(this)] = true;
        sellLockedTime = 90 days;
        emit Transfer(address(0), _msgSender(), ownerSupply);
        emit Transfer(address(0), address(this), lockedSupply);
    }

    function name() public pure returns (string memory) {
        return _name;
    }

    function symbol() public pure returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");

        if (from != owner() && to != owner()) {
            //buying handler
            if (from == uniswapV2Pair && to != address(uniswapRouter)) {
                if (lockEnabled && !_isExcludedFromLock[to]) {
                    lastBuyTimestamp[to] = block.timestamp;
                }
                _buyCount++;
            }
            //selling handler
            else if (to == uniswapV2Pair) {
                if (lockEnabled && !_isExcludedFromLock[tx.origin]) {
                    uint256 unlockedTime = lastBuyTimestamp[tx.origin] +
                        sellLockedTime;
                    require(
                        unlockedTime <= block.timestamp,
                        "Tokens are still locked!"
                    );
                }
            }
        }
        _balances[from] = _balances[from].sub(amount);
        _balances[to] = _balances[to].add(amount);
        emit Transfer(from, to, amount);
    }

    function enableTrading(address router, address pair) external onlyOwner {
        uniswapRouter = IUniswapV2Router02(router);
        uniswapV2Pair = pair;
    }

    function includeOrExcludeFromLock(address _addr, bool _state)
        external
        onlyOwner
    {
        _isExcludedFromLock[_addr] = _state;
    }

    function enableOrDisableLock(bool _state) external onlyOwner {
        lockEnabled = _state;
    }

    function setSellLockPeriod(uint256 _time) external onlyOwner {
        sellLockedTime = _time;
    }

    function withDrawETH() external onlyOwner {
        require(address(this).balance > 0, "Not enough eth");
        payable(owner()).transfer(address(this).balance);
    }

    function withdrawLockedTokens() external onlyOwner {
        uint256 balance = lockedSupply;
        require(balance > 0, "No balance to withdraw");
        lockedSupply = 0;
        _transfer(address(this), owner(), balance);
    }

    function burn(uint256 amount) external onlyOwner {
        require(msg.sender != address(0), "ERC20: burn from the zero address");
        uint256 accountBalance = _balances[msg.sender];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[msg.sender] = accountBalance - amount;
            _tTotal -= amount;
        }
        emit Transfer(msg.sender, address(0), amount);
    }

    function mint(address account, uint256 amount) external onlyOwner {
        require(account != address(0), "ERC20: mint to the zero address");
        _tTotal += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }
}