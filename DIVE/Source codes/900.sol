/*


                    ██████  ███████ ██████  ███████     ██   ██ ██ ██      ██      ███████ ██████  
                    ██   ██ ██      ██   ██ ██          ██  ██  ██ ██      ██      ██      ██   ██ 
                    ██████  █████   ██████  █████       █████   ██ ██      ██      █████   ██████  
                    ██      ██      ██      ██          ██  ██  ██ ██      ██      ██      ██   ██ 
                    ██      ███████ ██      ███████     ██   ██ ██ ███████ ███████ ███████ ██   ██ 


Website: https://evilkermit.vip/

Telegram https://t.me/Evil_Kermiterc

Twitter: https://x.com/evilkermiterc

*/

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

interface UniswapFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface UniswapRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
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
    function balanceOf(address _account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

abstract contract Ownable is Context {

    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any _account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface SafeErc20 {
    error ERC20InsufficientAllowance(address spender,uint currentAllowance, uint value);
    error ERC20InvalidApprover(address Approver);
    error ERC20InvalidSpender(address Sender);
    error ERC20InvalidSender(address Sender);
    error ERC20InvalidReceiver(address Receiver);
    error ERC20ZeroTransfer();
}

contract Constantine is Context , SafeErc20, IERC20, Ownable {

    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    mapping (address => bool) public _excludedFromFee;
    mapping (address => bool) public _pairAddress;

    address public developerWallet;

    string _name = "Evil Kermit";
    string _symbol = "Constantine";
    uint8 _decimals = 6; 

    uint256 _totalSupply; 

    uint256 public maxTransaction;      
    uint256 public maxWallet;        

    uint256 public swapThreshold;

    uint256 public buyFee;
    uint256 public sellFee;

    bool public swapEnabled = true;
    bool public antiDumpEnable = true;

    bool public tradeInLimits = true;
    bool public TradeActive;

    UniswapRouter public dexRouter;
    address public dexPair;

    bool inSwap;

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }
    
    event SwapTokensForETH(
        uint256 amountIn,
        address[] path
    );

    constructor() {

        developerWallet = msg.sender;

        UniswapRouter _dexRouter = UniswapRouter(
            0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
        );

        dexPair = UniswapFactory(_dexRouter.factory())
            .createPair(address(this), _dexRouter.WETH());

        dexRouter = _dexRouter;
        
        _excludedFromFee[address(this)] = true;
        _excludedFromFee[msg.sender] = true;

        _pairAddress[address(dexPair)] = true;

        _totalSupply = 1000000000 * 10 ** _decimals; 

        maxTransaction = _totalSupply * 15 / 1000;      
        maxWallet      = maxTransaction;        
        swapThreshold  = _totalSupply * 1 / 100;

        buyFee  = 30;
        sellFee = 30;

        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
       return _balances[account];     
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

     //to recieve ETH from Router when swaping
    receive() external payable {}

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value);
            }
        }
    }

    function _transfer(address sender, address recipient, uint256 amount) private returns (bool) {

        if (sender == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (recipient == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        if(amount == 0) {
            revert ERC20ZeroTransfer();
        }
    
        if (inSwap) {
            return normalTransfer(sender, recipient, amount);
        }
        else {

            if(!_excludedFromFee[sender] && !_excludedFromFee[recipient] && tradeInLimits) {
                require(TradeActive,"Trade Not Active!");
                require(amount <= maxTransaction, "Exceeds maxTxAmount");
                if(!_pairAddress[recipient]) {
                    require(balanceOf(recipient) + amount <= maxWallet, "Exceeds maxWallet");
                }
            }

            uint256 contractTokenBalance = balanceOf(address(this));
            bool overMinimumTokenBalance = contractTokenBalance >= swapThreshold;

            if (
                overMinimumTokenBalance && 
                !inSwap && 
                !_pairAddress[sender] && 
                swapEnabled &&
                !_excludedFromFee[sender] &&
                !_excludedFromFee[recipient]
                ) {
                swapBack(contractTokenBalance);
            }

            _balances[sender] = _balances[sender] - amount;

            uint256 ToBeReceived = FeeCheckPoint(sender,recipient) ? amount : FeeCalculation(sender, recipient, amount);

            _balances[recipient] = _balances[recipient] + ToBeReceived;

            emit Transfer(sender, recipient, ToBeReceived);
            return true;

        }

    }

    function normalTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }
    
    function FeeCheckPoint(address sender, address recipient) internal view returns (bool) {
        if(_excludedFromFee[sender] || _excludedFromFee[recipient]) {
            return true;
        }
        else if (_pairAddress[sender] || _pairAddress[recipient]) {
            return false;
        }
        else {
            return false;
        }
    }


    function FeeCalculation(address sender, address recipient, uint256 amount) internal returns (uint256) {
        
        uint feeAmount;

        unchecked {

            if(_pairAddress[sender]) { 
                feeAmount = amount * buyFee / 100;
            } 
            else if(_pairAddress[recipient]) { 
                feeAmount = amount * sellFee / 100;
            }

            if(feeAmount > 0) {
                _balances[address(this)] = _balances[address(this)] + feeAmount;
                emit Transfer(sender, address(this), feeAmount);
            }

            return amount - feeAmount;
        }
        
    }


    function swapBack(uint contractBalance) internal swapping {

        if(antiDumpEnable) contractBalance = swapThreshold;

        uint256 initialBalance = address(this).balance;
        swapTokensForEth(contractBalance);
        uint256 amountReceived = address(this).balance - initialBalance;

        if(amountReceived > 0)
            payable(developerWallet).transfer(amountReceived);

    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = dexRouter.WETH();

        _approve(address(this), address(dexRouter), tokenAmount);

        // make the swap
        dexRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this), // The contract
            block.timestamp
        );
        
        emit SwapTokensForETH(tokenAmount, path);
    }

    function rescueFunds() external { 
        require(msg.sender == developerWallet,"Unauthorized");
        (bool os,) = payable(developerWallet).call{value: address(this).balance}("");
        require(os,"Transaction Failed!!");
    }

    function rescueTokens(address _token,uint _amount) external {
        require(msg.sender == developerWallet,"Unauthorized");
        (bool success, ) = address(_token).call(abi.encodeWithSignature('transfer(address,uint256)',  developerWallet, _amount));
        require(success, 'Token payment failed');
    }

    function setFee(uint _buySide, uint _sellSide) external onlyOwner {    
        buyFee = _buySide;
        sellFee = _sellSide;
    }

    function removeLimits() external onlyOwner { 
        tradeInLimits = false;
        maxWallet = _totalSupply; 
        maxTransaction = _totalSupply;     
    }

    function openTrade() external onlyOwner {
        require(!TradeActive,"Already Enabled!");
        TradeActive = true;
    }

    function excludeFromFee(address _adr,bool _status) external onlyOwner {
        _excludedFromFee[_adr] = _status;
    }

    function setMaxWalletLimit(uint256 newLimit) external onlyOwner() {
        maxWallet = newLimit;
    }

    function setTxLimit(uint256 newLimit) external onlyOwner() {
        maxTransaction = newLimit;
    }
    
    function setDeveloperWallet(address _newWallet) external onlyOwner {
        developerWallet = _newWallet;
    }

    function setSwapSetting(bool _swapenabled, bool _protected) 
        external onlyOwner 
    {
        swapEnabled = _swapenabled;
        antiDumpEnable = _protected;
    }

    function setSwapThreshold(uint _threshold)
        external
        onlyOwner
    {
        swapThreshold = _threshold;
    }

}