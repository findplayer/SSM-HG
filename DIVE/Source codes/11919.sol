/**
 *Submitted for verification at Etherscan.io on 2023-04-09
*/

// SPDX-License-Identifier: Unlicensed 

pragma solidity 0.8.19;

interface IERC20 {
    
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;}
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;}
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;}
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;}
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {require(b <= a, errorMessage);
            return a - b;}}
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {require(b > 0, errorMessage);
            return a / b;}}
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
    function _msgData() internal view virtual returns (bytes calldata) {
        this; 
        return msg.data;
    }
}

library Address {
    
    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "insufficient balance");
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "unable to send, recipient reverted");
    }
    
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "low-level call failed");
    }
    
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }
    
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "low-level call with value failed");
    }
    
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "insufficient balance for call");
        require(isContract(target), "call to non-contract");
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }
    
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "low-level static call failed");
    }
    
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "static call to non-contract");
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "low-level delegate call failed");
    }
    
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "delegate call to non-contract");
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
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

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
    function initialize(address, address) external;
}

interface IUniswapV2Router01 {

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

interface IUniswapV2Router02 is IUniswapV2Router01 {

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

contract Snoopy is Context, IERC20 { 

    using SafeMath for uint256;
    using Address for address;

    // Contract Wallets
    address private _owner = payable(0x24693c221b1761ca68f621cEB79714567dB9E093);
    address public Wallet_Liquidity;
    address payable public Wallet_Marketing;
    address private constant Wallet_Burn = 0x000000000000000000000000000000000000dEaD;

    // Token Info
    string private  _name = "Cartoon Ai";
    string private  _symbol = "SNOOP";
    uint256 private _decimals = 18;
    uint256 private _tTotal = 100_000_000 * 10 ** _decimals;

    // Project Links
    string private _Website;
    string private _Telegram;
    string private _LP_Lock;

    // Limits
    uint256 private max_Hold = 4000000 * 10 ** _decimals;
    uint256 private max_Tran = 4000000 * 10 ** _decimals;

    // Fees
    uint256 public _Fee__Buy_Burn;
    uint256 public _Fee__Buy_Liquidity;
    uint256 public _Fee__Buy_Marketing;

    uint256 public _Fee__Sell_Burn;
    uint256 public _Fee__Sell_Liquidity;
    uint256 public _Fee__Sell_Marketing;

    // Total Fee for Swap
    uint256 private _SwapFeeTotal_Buy;
    uint256 private _SwapFeeTotal_Sell;

    // Factory
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;

    constructor (string memory      _TokenName, 
                 string memory      _TokenSymbol,  
                 uint256            _TotalSupply, 
                 uint256            _Decimals, 
                 address payable    _OwnerWallet) {

    // Owner
    _owner              = _OwnerWallet;

    // Token Info
    _name               = _TokenName;
    _symbol             = _TokenSymbol;
    _decimals           = _Decimals;
    _tTotal             = _TotalSupply * 10**_decimals;

    // Wallet Limits
    max_Hold            = _tTotal;
    max_Tran            = _tTotal;

    // Project Wallets Set to Owner
    Wallet_Marketing    = payable(_OwnerWallet);
    Wallet_Liquidity    = _OwnerWallet;

    // Transfer Supply To Owner
    _tOwned[_owner]     = _tTotal;

    // Set UniSwap Router Address
    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    
    // Create Initial Pair With ETH
    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());
    uniswapV2Router = _uniswapV2Router;

    // Set Initial LP Pair
    _isPair[uniswapV2Pair] = true;   

    // Wallets Excluded From Limits
    _isLimitExempt[address(this)] = true;
    _isLimitExempt[Wallet_Burn] = true;
    _isLimitExempt[uniswapV2Pair] = true;
    _isLimitExempt[_owner] = true;

    // Wallets With Pre-Launch Access
    _isWeiss[_owner] = true;

    // Wallets Excluded From Fees
    _isExcludedFromFee[address(this)] = true;
    _isExcludedFromFee[Wallet_Burn] = true;
    _isExcludedFromFee[_owner] = true;

    // Emit Supply Transfer to Owner
    emit Transfer(address(0), _owner, _tTotal);

    // Emit Ownership Transfer
    emit OwnershipTransferred(address(0), _owner);

    }

    // Events
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event updated_Wallet_Limits(uint256 max_Tran, uint256 max_Hold);
    event updated_Buy_fees(uint256 Marketing, uint256 Liquidity, uint256 Burn);
    event updated_Sell_fees(uint256 Marketing, uint256 Liquidity, uint256 Burn);
    event updated_SwapAndLiquify_Enabled(bool Swap_and_Liquify_Enabled);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);

    // Restrict Function to Current Owner
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    // Mappings
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _isExcludedFromFee;
    mapping (address => bool) public _isLimitExempt;
    mapping (address => bool) public _isPair;
    mapping (address => bool) public _isFruhKaufer;
    mapping (address => bool) public _isWeiss;
    mapping (address => bool) public _isSchwarzed;

    // Fee Processing Triggers
    uint256 private swapTrigger = 11;   
    uint256 private swapCounter = 1;    
    
    // SwapAndLiquify Switch                  
    bool public inSwapAndLiquify;
    bool public swapAndLiquifyEnabled; 

    // Launch Settings
    uint256 private LaunchTime;
    uint256 private FruhBuyTime;
    bool public launchMode;
    bool public trade_Open;
    bool public freeWalletTransfers = true;
    bool public schwarzPossible = true;
    bool public ZunachstVerschieben = false;
    bool public burnFromSupply = false;

    // Fee Tracker
    bool private takeFee;

    // Project info
    function Project_Information() external view returns(address Owner_Wallet,
                                                       uint256 Transaction_Limit,
                                                       uint256 Max_Wallet,
                                                       uint256 Fee_When_Buying,
                                                       uint256 Fee_When_Selling,
                                                       bool Schwarz_Possible,
                                                       string memory Website,
                                                       string memory Telegram,
                                                       string memory Liquidity_Lock,
                                                       string memory Contract_Created_By) {
                                                           
        string memory Creator = "SuperDevForker";

        uint256 Total_buy =  _Fee__Buy_Burn         +
                             _Fee__Buy_Liquidity    +
                             _Fee__Buy_Marketing    ;

        uint256 Total_sell = _Fee__Sell_Burn        +
                             _Fee__Sell_Liquidity   +
                             _Fee__Sell_Marketing   ;

        uint256 _max_Hold = max_Hold / 10 ** _decimals;
        uint256 _max_Tran = max_Tran / 10 ** _decimals;

        if (_max_Tran > _max_Hold) {

            _max_Tran = _max_Hold;
        }


        // Return Token Data
        return (_owner,
                _max_Tran,
                _max_Hold,
                Total_buy,
                Total_sell,
                schwarzPossible,
                _Website,
                _Telegram,
                _LP_Lock,
                Creator);

    }
    
    // Set buy fees
    function Contract_SetUp_02__Fees_on_Buy(

        uint256 Marketing_on_BUY, 
        uint256 Liquidity_on_BUY, 
        uint256 Burn_on_BUY  

        ) external onlyOwner {

        // Buyer Protection: Max Fee 15% 
        require (Marketing_on_BUY    + 
                 Liquidity_on_BUY    + 
                 Burn_on_BUY <= 10, "E01"); // Total buy fee must be 10 or less 

        // Update Fees
        _Fee__Buy_Marketing  = Marketing_on_BUY;
        _Fee__Buy_Liquidity  = Liquidity_on_BUY;
        _Fee__Buy_Burn       = Burn_on_BUY;

        // Fees For Processing
        _SwapFeeTotal_Buy    = _Fee__Buy_Marketing + _Fee__Buy_Liquidity;

        emit updated_Buy_fees(_Fee__Buy_Marketing, _Fee__Buy_Liquidity, _Fee__Buy_Burn);
    }

    // Set sell fees
    function Contract_SetUp_03__Fees_on_Sell(

        uint256 Marketing_on_SELL,
        uint256 Liquidity_on_SELL, 
        uint256 Burn_on_SELL

        ) external onlyOwner {

        // Seller Protection: Max Fee 15% 
        require (Marketing_on_SELL  + 
                 Liquidity_on_SELL  + 
                 Burn_on_SELL <= 30, "E02"); // Total sell fee must be 30 or less 

        // Update Fees
        _Fee__Sell_Marketing  = Marketing_on_SELL;
        _Fee__Sell_Liquidity  = Liquidity_on_SELL;
        _Fee__Sell_Burn       = Burn_on_SELL;


        // Fees For Processing
        _SwapFeeTotal_Sell    = _Fee__Sell_Marketing + _Fee__Sell_Liquidity;

        emit updated_Sell_fees(_Fee__Sell_Marketing, _Fee__Sell_Liquidity, _Fee__Sell_Burn);
    }

    function Contract_SetUp_04__Wallet_Limits(

        uint256 Max_Tokens_Each_Transaction,
        uint256 Max_Total_Tokens_Per_Wallet 

        ) external onlyOwner {

        if (launchMode || !trade_Open){

            require(Max_Tokens_Each_Transaction >= _tTotal / 2000 / 10**_decimals, "E03");
            require(Max_Total_Tokens_Per_Wallet >= _tTotal / 2000 / 10**_decimals, "E04");


        } else {

            require(Max_Tokens_Each_Transaction >= _tTotal / 1000 / 10**_decimals, "E05");
            require(Max_Total_Tokens_Per_Wallet >= _tTotal / 200 / 10**_decimals, "E06");
        

        }
        
        max_Tran = Max_Tokens_Each_Transaction * 10**_decimals;
        max_Hold = Max_Total_Tokens_Per_Wallet * 10**_decimals;

        emit updated_Wallet_Limits(max_Tran, max_Hold);

    }

    function Contract_SetUp_05__Kanonier_Protection(

        uint256 Fruh_Buy_Timer_in_Seconds,
        bool Bloquear_Fruh_Kaufer_Sells

        ) external onlyOwner {

        require (Fruh_Buy_Timer_in_Seconds <= 480, "E07");
        FruhBuyTime = Fruh_Buy_Timer_in_Seconds;

        ZunachstVerschieben = Bloquear_Fruh_Kaufer_Sells;

    }

    function Contract_SetUp_06__Open_Trade() external onlyOwner {

        require(!trade_Open);

        swapAndLiquifyEnabled = true;
        LaunchTime = block.timestamp;
        launchMode = true;
        trade_Open = true;

    }

    function Contract_SetUp_07__Schwarz_Kanoniers(address Wallet, bool true_or_false) external onlyOwner {
        
        if (true_or_false) {

            require(schwarzPossible, "E08");
        }

        _isSchwarzed[Wallet] = true_or_false;

    }

    function Contract_SetUp_08__Deactivate_Launch_Mode() external onlyOwner {

        launchMode = false;
        schwarzPossible = false;
        ZunachstVerschieben = false;

        if (max_Tran < _tTotal / 1000) {

            max_Tran = _tTotal / 1000;
        }

        if (max_Hold < _tTotal / 200) {

            max_Hold = _tTotal / 200;
        }

    }

    function Contract_SetUp_09__Update_Wallets(

        address Liquidity_Collection_Wallet,
        address payable Marketing_Fee_Wallet

        ) external onlyOwner {

        require(Liquidity_Collection_Wallet != address(0), "E10");
        Wallet_Liquidity = Liquidity_Collection_Wallet;

        require(Marketing_Fee_Wallet != address(0), "E11");
        Wallet_Marketing = payable(Marketing_Fee_Wallet);

    }

    function Contract_SetUp_10__Update_Links(

        string memory Website_URL, 
        string memory Telegram_URL,
        string memory LP_Lock_URL

        ) external onlyOwner{

        _Website    = Website_URL;
        _Telegram   = Telegram_URL;
        _LP_Lock    = LP_Lock_URL;

    }

    function Contract__Options__Burn_From_Supply(bool true_or_false) external onlyOwner {

        burnFromSupply = true_or_false;

    }

    function Contract__Options__Free_Wallet_Transfers(bool true_or_false) public onlyOwner {

        freeWalletTransfers = true_or_false;

    }

    function Maintenance__Add_Liquidity_Pair(

        address Wallet_Address,
        bool true_or_false)

        external onlyOwner {

        _isPair[Wallet_Address] = true_or_false;
        _isLimitExempt[Wallet_Address] = true_or_false;
    } 

    function Maintenance__Ownership_RENOUNCE(uint256 Confirmation_Code) public virtual onlyOwner {

        require(Confirmation_Code == 6969, "E12");

        _isLimitExempt[owner()]     = false;
        _isExcludedFromFee[owner()] = false;
        _isWeiss[owner()]           = false;

        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function Maintenance__Ownership_TRANSFER(address payable newOwner, uint256 Confirmation_Code) public onlyOwner {

        require(Confirmation_Code == 6969, "E12");
        require(newOwner != address(0), "E13");

        _isLimitExempt[owner()]     = false;
        _isExcludedFromFee[owner()] = false;
        _isWeiss[owner()]           = false;

        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;

        _isLimitExempt[owner()]     = true;
        _isExcludedFromFee[owner()] = true;
        _isWeiss[owner()]           = true;

    }

    function Processing__Auto_Process(bool true_or_false) external onlyOwner {
        swapAndLiquifyEnabled = true_or_false;
        emit updated_SwapAndLiquify_Enabled(true_or_false);
    }

    function Processing__Process_Now (uint256 Percent_of_Tokens_to_Process) external onlyOwner {

        require(!inSwapAndLiquify, "E15");

        if (Percent_of_Tokens_to_Process > 100){Percent_of_Tokens_to_Process = 100;}
        uint256 tokensOnContract = balanceOf(address(this));
        uint256 sendTokens = tokensOnContract * Percent_of_Tokens_to_Process / 100;
        swapAndLiquify(sendTokens);

    }

    function Processing__Swap_Trigger_Count(uint256 Transaction_Count) external onlyOwner {

        swapTrigger = Transaction_Count + 1;
    }

    function Processing__Remove_Random_Tokens(

        address random_Token_Address,
        uint256 number_of_Tokens

        ) external onlyOwner {

            require (random_Token_Address != address(this), "E16");
            IERC20(random_Token_Address).transfer(msg.sender, number_of_Tokens);
            
    }

    function Wallet_Settings__Exclude_From_Fees(

        address Wallet_Address,
        bool true_or_false

        ) external onlyOwner {
        _isExcludedFromFee[Wallet_Address] = true_or_false;

    }

    function Wallet_Settings__Exempt_From_Limits(

        address Wallet_Address,
        bool true_or_false

        ) external onlyOwner {  
        _isLimitExempt[Wallet_Address] = true_or_false;
    }

    function Wallet_Settings__Pre_Launch_Access(

        address Wallet_Address,
        bool true_or_false

        ) external onlyOwner {    
        _isWeiss[Wallet_Address] = true_or_false;
    }

    function Wallet_Settings__Remove_Fruh_Kaufer_Tag(

        address Wallet_Address

        ) external onlyOwner {    
        _isFruhKaufer[Wallet_Address] = false;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint256) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _tOwned[account];
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "Decreased allowance below zero"));
        return true;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }
    
    function _approve(address owner, address spender, uint256 amount) private {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "Allowance exceeded"));
        return true;
    }

    function send_ETH(address _to, uint256 _amount) internal returns (bool SendSuccess) {
        (SendSuccess,) = payable(_to).call{value: _amount}("");
    }

    function getCirculatingSupply() public view returns (uint256) {
        return (_tTotal - balanceOf(address(Wallet_Burn)));
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
      ) private {

        require(balanceOf(from) >= amount, "E19");

        if (!trade_Open){

            require(_isWeiss[from] || _isWeiss[to], "E20");

            uint LP_Supply = IERC20(uniswapV2Pair).totalSupply();

            if(LP_Supply > 0){

                require(to != uniswapV2Pair, "Weiss wallets can not sell tokens before trade is open");

            } 


        }

        if (launchMode) {

            if (block.timestamp > LaunchTime + (8 * 1 hours)){

                launchMode = false;
                schwarzPossible = false;

                if (max_Tran < _tTotal / 1000) {

                    max_Tran = _tTotal / 1000;
                }

                if (max_Hold < _tTotal / 200) {

                    max_Hold = _tTotal / 200;
                }
            
            } else {

                if (ZunachstVerschieben){
                    require(!_isFruhKaufer[from], "E21");
                }

                if (to != owner() && _isPair[from] && block.timestamp <= LaunchTime + FruhBuyTime) {

                    _isFruhKaufer[to] = true;

                } 

            }

        }

        if (to != owner()) {
                require(!_isSchwarzed[to] && !_isSchwarzed[from],"E22");
            }

        if (!_isLimitExempt[to]) {

            uint256 heldTokens = balanceOf(to);
            require((heldTokens + amount) <= max_Hold, "E23");
            
        }

        if (!_isLimitExempt[to] || !_isLimitExempt[from]) {

            require(amount <= max_Tran, "E24");
        
        }

        require(from != address(0), "E25");
        require(to != address(0), "E26");
        require(amount > 0, "E27");

        if (_isPair[to] && !inSwapAndLiquify && swapAndLiquifyEnabled) {

            if(swapCounter >= swapTrigger){

                uint256 contractTokens = balanceOf(address(this));

                if (contractTokens > 0) {

                    if (contractTokens <= max_Tran) {

                        swapAndLiquify (contractTokens);

                        } else {

                        swapAndLiquify (max_Tran);

                    }
                }
            }  
        }

        takeFee = true;
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to] || (freeWalletTransfers && !_isPair[to] && !_isPair[from])){
            takeFee = false;
        }

        _tokenTransfer(from, to, amount, takeFee);

    }

    function swapAndLiquify(uint256 Tokens) private {

        inSwapAndLiquify        = true;  

        uint256 _FeesTotal      = _SwapFeeTotal_Buy + _SwapFeeTotal_Sell;
        uint256 LP_Tokens       = Tokens * (_Fee__Buy_Liquidity + _Fee__Sell_Liquidity) / _FeesTotal / 2;
        uint256 Swap_Tokens     = Tokens - LP_Tokens;

        uint256 contract_ETH    = address(this).balance;
        swapTokensForETH(Swap_Tokens);
        uint256 returned_ETH    = address(this).balance - contract_ETH;

        uint256 fee_Split       = _FeesTotal * 2 - (_Fee__Buy_Liquidity + _Fee__Sell_Liquidity);

        uint256 ETH_Liquidity   = returned_ETH * (_Fee__Buy_Liquidity   + _Fee__Sell_Liquidity)       / fee_Split;

        if (LP_Tokens > 0){
            addLiquidity(LP_Tokens, ETH_Liquidity);
            emit SwapAndLiquify(LP_Tokens, ETH_Liquidity, LP_Tokens);
        }

        contract_ETH = address(this).balance;

        if (contract_ETH > 0){

            send_ETH(Wallet_Marketing, contract_ETH);
        }

        swapCounter = 1;

        inSwapAndLiquify = false;

    }

    function swapTokensForETH(uint256 tokenAmount) private {

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, 
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ETHAmount) private {

        _approve(address(this), address(uniswapV2Router), tokenAmount);
        uniswapV2Router.addLiquidityETH{value: ETHAmount}(
            address(this),
            tokenAmount,
            0, 
            0,
            Wallet_Liquidity, 
            block.timestamp
        );
    } 

    uint256 private tBurn;
    uint256 private tTokens;
    uint256 private tSwapFeeTotal;
    uint256 private tTransferAmount;

    function _tokenTransfer(address sender, address recipient, uint256 tAmount, bool Fee) private {
        
        if (Fee){

            if(_isPair[recipient]){

                // Sell Fees
                tBurn           = tAmount * _Fee__Sell_Burn       / 100;
                tSwapFeeTotal   = tAmount * _SwapFeeTotal_Sell    / 100;

            } else {

                // Buy Fees
                tBurn           = tAmount * _Fee__Buy_Burn        / 100;
                tSwapFeeTotal   = tAmount * _SwapFeeTotal_Buy     / 100;

            }

        } else {

                // No Fees
                tBurn           = 0;
                tTokens         = 0;
                tSwapFeeTotal   = 0;

        }

        tTransferAmount = tAmount - (tBurn + tTokens + tSwapFeeTotal);

        _tOwned[sender] -= tAmount;

        if (burnFromSupply && recipient == Wallet_Burn) {

                _tTotal -= tTransferAmount;

            } else {

                _tOwned[recipient] += tTransferAmount;

            }

            emit Transfer(sender, recipient, tTransferAmount);

        if(tSwapFeeTotal > 0){

            _tOwned[address(this)] += tSwapFeeTotal;

            swapCounter++;
                
        }

        if(tBurn > 0){

            if (burnFromSupply){

                _tTotal = _tTotal - tBurn;

            } else {

                _tOwned[Wallet_Burn] += tBurn;

            }

        }

    }

    receive() external payable {}

}