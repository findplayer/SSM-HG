/*

░██████╗░██╗░░░██╗░█████╗░██████╗░██╗░░██╗  ██████╗░░░░░█████╗░
██╔═══██╗██║░░░██║██╔══██╗██╔══██╗██║░██╔╝  ╚════██╗░░░██╔══██╗
██║██╗██║██║░░░██║███████║██████╔╝█████═╝░  ░█████╔╝░░░██║░░██║
╚██████╔╝██║░░░██║██╔══██║██╔══██╗██╔═██╗░  ░╚═══██╗░░░██║░░██║
░╚═██╔═╝░╚██████╔╝██║░░██║██║░░██║██║░╚██╗  ██████╔╝██╗╚█████╔╝
░░░╚═╝░░░░╚═════╝░╚═╝░░╚═╝╚═╝░░╚═╝╚═╝░░╚═╝  ╚═════╝░╚═╝░╚════╝░


Website:  https://www.quarktoken.io
Marketplace: https://quarkmarket.com
Telegram: https://t.me/QuarkToken
Twitter:  @QuarkToken

CEO: @jimango
CA author: @bLock_doctor

*/
// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.12;
 
library Address {
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");
        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }
    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            if (returndata.length > 0) {
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}
interface IUniRouterV1
{
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
 
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}
interface IUniRouterV2 is IUniRouterV1
{
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }
    function owner() public view returns (address) {
        return _owner;
    }
    modifier onlyOwner() {
        require(msg.sender==owner(), "Ownable: caller is not the owner");
        _;
    }
    function renounceOwnership() public virtual onlyOwner {
        _owner = address(0);
        emit OwnershipTransferred(_owner, address(0));
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _owner = newOwner;
        emit OwnershipTransferred(_owner, newOwner);
    }
}
contract QuarkToken3 is IERC20, Ownable {

    uint8 private _buyTax = 5;
    uint8 private _sellTax = 5;
    uint8 private constant _decimals = 18;

    uint256 private constant _totalSupply = 10000000000000 * 10 ** _decimals; // 10T
    uint256 private _swapTokenThreshold = 50000000000 * 10 ** _decimals;

    string private constant _tokenName = "Quark 3.0 Token";
    string private constant _tokenSymbol = "QUARK 3";

    bool private _tradingEnabled;
    bool private _swapEnabled;
    bool private _inSwap;

    IUniRouterV2 private _router;
    address private _pairAddress;
    address public constant quarkCEO = address(0x6F0a450e3C949f3063f625f1004C360Ef4d2B49e);
    address public constant burnWallet = address(0xdead);
    address public constant zeroAddress = address(0);

    mapping(address => uint256) private _balances;
    mapping(address => bool) private _excludedFromFees;
    mapping(address => bool) private _automatedMarketMakers;
    mapping(address => mapping (address => uint256)) private _allowances;

    modifier LockTheSwap {
        _inSwap = true;
        _;
        _inSwap = false;
    }
    constructor() {
        _excludedFromFees[msg.sender] = true;
        _excludedFromFees[address(this)] = true;
        _excludedFromFees[burnWallet] = true;
        _excludedFromFees[zeroAddress] = true;
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        bool isExcluded = _excludedFromFees[from] || _excludedFromFees[to];
        bool isBuy = _automatedMarketMakers[from];
        bool isSell = _automatedMarketMakers[to];
        if (isExcluded) _transferTokens(from, to, amount, 0);
        else {
            require(_tradingEnabled, "Trading is not enabled!");
            if (isBuy) _transferTokens(from, to, amount, _buyTax);
            else if (isSell) {
                if (!_inSwap && _swapEnabled) _swapContractTokens();
                _transferTokens(from, to, amount, _sellTax);
            } else _transferTokens(from, to, amount, 0);
        }
    }
    function _transferTokens(
        address from,
        address to,
        uint256 amount,
        uint8 taxPercent
    ) private {
        uint256 taxAmount = amount * taxPercent / 100;
        _balances[from] -= amount;
        _balances[address(this)] += taxAmount;
        _balances[to] += amount - taxAmount;
        emit Transfer(from, to, amount - taxAmount);
    }
    function _swapContractTokens() private LockTheSwap {
        uint256 contractTokenBalance = _balances[address(this)];
        if (contractTokenBalance >= _swapTokenThreshold) {
            uint256 oldETH = address(this).balance;
            _swapTokensForETH(contractTokenBalance);
            uint256 newETH = address(this).balance - oldETH;
            require(newETH > 0);
            (bool transferMarketing,) = payable(quarkCEO).call{value: address(this).balance, gas: 30000}("");
            require(transferMarketing, "Error transferring ETH.");
        }
    }
    // LIQUIDTY FUNCTIONS \\
    function _swapTokensForETH(
        uint256 tokenAmount
    ) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = _router.WETH();
        _approve(address(this), address(_router), tokenAmount);
        _router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, 
            path,
            address(this),
            block.timestamp
        );
    }
    // OWNER FUNCTIONS \\ 
    function ownerCreatePair(
        address routerAddress
    ) public onlyOwner {
        require(!_tradingEnabled, "Cannot create pair after trading enabled!");
        _router = IUniRouterV2(routerAddress);
        _pairAddress = IDEXFactory(_router.factory()).createPair(_router.WETH(), address(this));
        _allowances[address(this)][address(_router)] = type(uint256).max;
        _automatedMarketMakers[_pairAddress] = true;
    }
    // Trading can only be enabled, not disabled.
    function ownerEnableTrading() public onlyOwner {
        require(!_tradingEnabled, "Cannot disable trading!");
        _tradingEnabled = !_tradingEnabled;
    }
    // Swap tokens from contract for ETH / ALV
    function ownerTriggerSwap() public onlyOwner {
        _swapContractTokens();
    }
    // Set taxes, buy tax + sell tax cannot exceed 10% .
    function ownerUpdateTax(
        uint8 buyTax,
        uint8 sellTax
    ) public onlyOwner {
        require(buyTax + sellTax <= 20, "Buy tax + sell tax cannot exceed 10% !");
        _buyTax = buyTax;
        _sellTax = sellTax;
    }
    // Exclude address from fees.
    function ownerExcludeFromFee(
        address account,
        bool enabled
    ) public onlyOwner {
        _excludedFromFees[account] = enabled;
    }
    function ownerToggleSwapEnabled(
        bool swapEnabled
    ) public onlyOwner {
        _swapEnabled = swapEnabled;
    }
    // Tokens to be sold by the contract.
    function ownerSetSwapThreshold(
        uint256 swapTokenThreshold
    ) public onlyOwner {
        require(_swapTokenThreshold > 0, "Must be greater than zero.");
        require(swapTokenThreshold <= 50000000000, "Cannot exceed 50 billion.");
        _swapTokenThreshold = swapTokenThreshold * 10 ** _decimals;
    }
    // Withdraw any stuck ETH balance in contract.
    function ownerWithdrawETH() public onlyOwner {
        (bool success,) = msg.sender.call{value: (address(this).balance)}("");
        require(success, "Error withdrawing ETH.");
    }
    // Remove foreign tokens from contract balance.
    function ownerWithdrawStrandedToken(
        address strandedToken
    ) public onlyOwner {
        require(strandedToken != _pairAddress && strandedToken != address(this));
        IERC20 token = IERC20(strandedToken);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }
    // END OF OWNER FUNCTIONS \\ 

    // START OF GETTERS \\
    function showTradeTaxes() public view returns (
        uint8 buyTax,
        uint8 sellTax
    ) {
        buyTax = _buyTax;
        sellTax = _sellTax;
    }
    function getPairAddress() public view returns (address) {
        return _pairAddress;
    }
    function isSwapEnabled() public view returns (bool) {
        return _swapEnabled;
    }
    function getSwapTokenThreshold() public view returns (uint256) {
        return _swapTokenThreshold;
    }
    // END OF GETTERS \\ 

    function transfer(
        address recipient, 
        uint256 amount
    ) external override returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }
    function transferFrom(
        address sender, 
        address recipient, 
        uint256 amount
    ) external override returns (bool) {
        uint256 allowance_ = _allowances[sender][msg.sender];
        _transfer(sender, recipient, amount);
        require(allowance_ >= amount);
        _approve(sender, msg.sender, allowance_ - amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }
    function _approve(
        address owner, 
        address spender, 
        uint256 amount
    ) private {
        require((owner != address(0) && spender != address(0)), "Owner/Spender address cannot be 0.");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
    function approve(
        address spender, 
        uint256 amount
    ) external override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    function allowance(
        address owner_,
        address spender
    ) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }
    function balanceOf(
        address account
    ) external view override returns (uint256) {
        return _balances[account];
    }
    function name() external pure returns (string memory) {
        return _tokenName;
    }
    function symbol() external pure returns (string memory) {
        return _tokenSymbol;
    }
    function totalSupply() external pure override returns (uint256) {
        return _totalSupply;
    }
    function decimals() external pure returns (uint8) {
        return _decimals;
    }
    function getOwner() external view returns (address) {
        return owner();
    }
    receive() external payable  {}
}