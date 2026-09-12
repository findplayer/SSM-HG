// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

contract Ownable {
    address _owner;

    event RenounceOwnership();

    constructor() {
        _owner = msg.sender;
    }

    modifier onlyOwner() {
        require(_owner == msg.sender, "only owner");
        _;
    }

    function owner() external view virtual returns (address) {
        return _owner;
    }

    function ownerRenounce() external onlyOwner {
        _owner = address(0);
        emit RenounceOwnership();
    }
}

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);

    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) external view returns (uint reserveA, uint reserveB);

    function getAmountsIn(
        uint amountOut,
        address[] memory path
    ) external view returns (uint[] memory amounts);

    function getAmountsOut(
        uint amountIn,
        address[] memory path
    ) external view returns (uint[] memory amounts);
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

contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) internal _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 internal _totalSupply;
    uint8 internal constant _decimals = 9;

    string private _name;
    string private _symbol;


    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }


    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(
        address account
    ) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }


    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }


    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
        return true;
    }


    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }


    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");

        uint256 fromBalance = _balances[from];
        require(
            fromBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        unchecked {
            _balances[from] = fromBalance - amount;
            // Overflow not possible: the sum of all balances is capped by totalSupply, and the sum is preserved by
            // decrementing then incrementing.
            _balances[to] += amount;
        }

        emit Transfer(from, to, amount);
    }


    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply += amount;
        unchecked {
            // Overflow not possible: balance + amount is at most totalSupply + amount, which is checked above.
            _balances[account] += amount;
        }
        emit Transfer(address(0), account, amount);
    }


    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
            // Overflow not possible: amount <= accountBalance <= totalSupply.
            _totalSupply -= amount;
        }

        emit Transfer(account, address(0), amount);
    }


    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }


    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}


abstract contract Pool is ERC20 {
    IUniswapV2Router02 constant uniswapV2Router =
        IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address internal _pair;
    uint256 internal _startTime;

    constructor(
        string memory name_,
        string memory symbol_
    ) ERC20(name_, symbol_) {}

    function createPair() external payable {
        _pair = IUniswapV2Factory(uniswapV2Router.factory()).createPair(
            address(this),
            uniswapV2Router.WETH()
        );
        _mint(address(this), createPairCount());
        _approve(address(this), address(uniswapV2Router), type(uint256).max);
        uniswapV2Router.addLiquidityETH{value: msg.value}(
            address(this),
            createPairCount(),
            0,
            0,
            msg.sender,
            block.timestamp
        );
        _startTime = block.timestamp;
    }

    function isStarted() internal view returns (bool) {
        return _pair != address(0);
    }

    function createPairCount() internal pure virtual returns (uint256);
}




contract AdultDoge is Pool {
    uint256 constant _startTotalSupply = 1e9 * (10 ** _decimals);
    uint256 constant _startMaxBuyCount = (_startTotalSupply * 5) / 10000;
    uint256 constant _addMaxBuyPercentPerSec = 10; // 
    uint256 constant _addMaxBuyPrecesion = 100000;
    uint256 public constant taxBuy = 200; // 100%=taxPrecesion
    uint256 public constant taxSell = 200; // 100%=taxPrecesion
    uint256 constant _taxPrecesion = 1000;
    uint256 constant _transferZeroTaxSeconds = 1000; // zero tax transfer time
    bool internal _feeLocked;

    constructor() Pool("Adult Doge", "OLD") {}

    modifier maxBuyLimit(uint256 amount) {
        require(amount <= maxBuy(), "max buy reached");
        _;
    }

    modifier lockFee() {
        _feeLocked = true;
        _;
        _feeLocked = false;
    }

    function createPairCount() internal pure override returns (uint256) {
        return _startTotalSupply;
    }

    function maxBuy() public view returns (uint256) {
        if (!isStarted()) return _startTotalSupply;
        uint256 count = _startMaxBuyCount +
            (_startTotalSupply *
                (block.timestamp - _startTime) *
                _addMaxBuyPercentPerSec) /
            _addMaxBuyPrecesion;
        if (count > _startTotalSupply) count = _startTotalSupply;
        return count;
    }

    function transferTax() public view returns (uint256) {
        if (!isStarted()) return 0;
        uint256 deltaTime = block.timestamp - _startTime;
        if (deltaTime >= _transferZeroTaxSeconds) return 0;
        return
            (_taxPrecesion * (_transferZeroTaxSeconds - deltaTime)) /
            _transferZeroTaxSeconds;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        // allow burning
        if (to == address(0)) {
            _burn(from, amount);
            return;
        }

        // system transfers
        if (from == address(0) || from == address(this)) {
            super._transfer(from, to, amount);
            return;
        }

        // transfers with fee
        if (_feeLocked) {
            super._transfer(from, to, amount);
            return;
        } else {
            if (from == _pair) {
                buy(to, amount);
                return;
            } else if (to == _pair) {
                sell(from, amount);
                return;
            } else transferFithFee(from, to, amount);
        }
    }

    function buy(
        address to,
        uint256 amount
    ) private maxBuyLimit(amount) lockFee {
        uint256 tax = (amount * taxBuy) / _taxPrecesion;
        if (tax > 0) _burn(_pair, tax);
        super._transfer(_pair, to, amount - tax);
    }

    function sell(address from, uint256 amount) private lockFee {
        uint256 tax = (amount * taxSell) / _taxPrecesion;
        if (tax > 0) _burn(from, tax);
        super._transfer(from, _pair, amount - tax);
    }

    function transferFithFee(
        address from,
        address to,
        uint256 amount
    ) private lockFee {
        uint256 tax = (amount * transferTax()) / _taxPrecesion;
        if (tax > 0) _burn(from, tax);
        super._transfer(from, to, amount - tax);
    }

    function burnCount() public view returns (uint256) {
        return _startTotalSupply - totalSupply();
    }
}