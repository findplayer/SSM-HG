/*
 * ███████ ██ ███    ██   ████   ███████ ███████  *
 * ██      ██ ████   ██  ██  ██  ██   ██ ██     
 * ██████  ██ ██ ██  ██ ████████ ███████ █████  
 * ██      ██ ██  ██ ██ ██    ██ ██      ██     
 * ██      ██ ██   ████ ██    ██ ██      ███████
 */

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

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
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

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
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
    function transferOwnership(address newOwner) public virtual onlyOwner {
        if (newOwner == address(0)) {
            revert OwnableInvalidOwner(address(0));
        }
        _transferOwnership(newOwner);
    }
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

interface IERC20Errors {
    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);
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

abstract contract ERC20 is Context, IERC20, IERC20Metadata, IERC20Errors {
    mapping(address account => uint256) private _balances;
    mapping(address account => mapping(address spender => uint256)) private _allowances;

    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }
    function name() public view virtual returns (string memory) {
        return _name;
    }
    function symbol() public view virtual returns (string memory) {
        return _symbol;
    }
    function decimals() public view virtual returns (uint8) {
        return 18;
    }
    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }
    function balanceOf(address account) public view virtual returns (uint256) {
        return _balances[account];
    }
    function transfer(address to, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, value);
        return true;
    }
    function allowance(address owner, address spender) public view virtual returns (uint256) {
        return _allowances[owner][spender];
    }
    function approve(address spender, uint256 value) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, value);
        return true;
    }
    function transferFrom(address from, address to, uint256 value) public virtual returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, value);
        _transfer(from, to, value);
        return true;
    }
    function _transfer(address from, address to, uint256 value) internal {
        if (from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(from, to, value);
    }
    function _update(address from, address to, uint256 value) internal virtual {
        if (from == address(0)) {
            _totalSupply += value;
        } else {
            uint256 fromBalance = _balances[from];
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                _balances[from] = fromBalance - value;
            }
        }

        if (to == address(0)) {
            unchecked {
                _totalSupply -= value;
            }
        } else {
            unchecked {
                _balances[to] += value;
            }
        }

        emit Transfer(from, to, value);
    }
    function _mint(address account, uint256 value) internal {
        if (account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(address(0), account, value);
    }
    function _approve(address owner, address spender, uint256 value) internal {
        _approve(owner, spender, value, true);
    }
    function _approve(address owner, address spender, uint256 value, bool emitEvent) internal virtual {
        if (owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        _allowances[owner][spender] = value;
        if (emitEvent) {
            emit Approval(owner, spender, value);
        }
    }
    function _spendAllowance(address owner, address spender, uint256 value) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < value) {
                revert ERC20InsufficientAllowance(spender, currentAllowance, value);
            }
            unchecked {
                _approve(owner, spender, currentAllowance - value, false);
            }
        }
    }
}

library Address {
    error AddressInsufficientBalance(address account);
    error FailedInnerCall();
    
    function sendValue(address payable recipient, uint256 amount) internal {
        if (address(this).balance < amount) {
            revert AddressInsufficientBalance(address(this));
        }

        (bool success, ) = recipient.call{value: amount}("");
        if (!success) {
            revert FailedInnerCall();
        }
    }
}

interface IRouter {
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

interface IFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

abstract contract Taxable is Context {
    event TaxOn(address account); 
    event TaxOff(address account); 
    event TaxRecipientChanged(address account); 
    event ExemptTax(address account);
    event ExemptTaxFrom(address account);
    event ExemptTaxTo(address account);
    event RevokeTaxExemption(address account);
    event RevokeTaxExemptionFrom(address account);
    event RevokeTaxExemptionTo(address account);

    bool private _taxed; 
    uint private _taxPoints; 
    uint private _burnPoints; 
    address private _taxRecipient;
    mapping (address => bool) private _taxExemption;
    mapping (address => bool) private _taxExemptionFrom;
    mapping (address => bool) private _taxExemptionTo;

    constructor(bool __taxed, uint __taxPoints, uint __burnPoints, address __taxRecipient) {
        _taxed = __taxed; 
        _taxPoints = __taxPoints; 
        _burnPoints = __burnPoints; 
        _taxRecipient = __taxRecipient; 
    }

    modifier whenNotTaxed() { 
        _requireNotTaxed();
        _;
    }

    modifier whenTaxed() { 
        _requireTaxed();
        _;
    }

    function isTaxed() public view virtual returns (bool) {
        return _taxed; 
    }

    function taxPoints() public view virtual returns (uint) {
        return _taxPoints;
    }

    function burnPoints() public view virtual returns (uint) {
        return _burnPoints;
    }

    function taxRecipient() public view virtual returns (address) {
        return _taxRecipient;
    }

    function isTaxExempted(address account) public view virtual returns (bool) { 
        return _taxExemption[account];
    }

    function isTaxExemptedFrom(address account) public view virtual returns (bool) { 
        return _taxExemptionFrom[account];
    }

    function isTaxExemptedTo(address account) public view virtual returns (bool) { 
        return _taxExemptionTo[account];
    }

    function _requireNotTaxed() internal view virtual {
        require(!isTaxed(), "Taxable: taxed");
    }

    function _requireTaxed() internal view virtual { 
        require(isTaxed(), "Taxable: not taxed");
    }

    function _taxOn() internal virtual whenNotTaxed {
        _taxed = true;
        emit TaxOn(_msgSender());
    }

    function _taxOff() internal virtual whenTaxed {
        _taxed = false;
        emit TaxOff(_msgSender());
    }

    function _updateTaxRecipient(address newRecipient) internal virtual {
        _taxRecipient = newRecipient;
        emit TaxRecipientChanged(_msgSender());
    }

    function _exemptTax(address account) internal virtual {
        require(!_taxExemption[account], "Account is already exempted");
        _taxExemption[account] = true;
        emit ExemptTax(account);
    }

    function _revokeTaxExemption(address account) internal virtual {
        require(_taxExemption[account], "Account is not exempted");
        _taxExemption[account] = false;
        emit RevokeTaxExemption(account);
    }

    function _exemptTaxFrom(address account) internal virtual {
        require(!_taxExemptionFrom[account], "Account is already exempted");
        _taxExemptionFrom[account] = true;
        emit ExemptTaxFrom(account);
    }

    function _revokeTaxExemptionFrom(address account) internal virtual {
        require(_taxExemptionFrom[account], "Account is not exempted");
        _taxExemptionFrom[account] = false;
        emit RevokeTaxExemptionFrom(account);
    }

    function _exemptTaxTo(address account) internal virtual {
        require(!_taxExemptionTo[account], "Account is already exempted");
        _taxExemptionTo[account] = true;
        emit ExemptTaxTo(account);
    }

    function _revokeTaxExemptionTo(address account) internal virtual {
        require(_taxExemptionTo[account], "Account is not exempted");
        _taxExemptionTo[account] = false;
        emit RevokeTaxExemptionTo(account);
    }
}

contract Finape is ERC20, Taxable, Ownable {
    using Address for address payable;

    IRouter public router;
    address public pair;
    bool _interlock;

    modifier lockTheSwap() {
        _interlock = true;
        _;
        _interlock = false;
    }

    constructor(
        string memory __name,
        string memory __symbol,
        address __routerAddress,
        bool __taxed,
        uint __taxPoints,
        uint __burnPoints,
        address __taxRecipient 
        )
        ERC20(__name, __symbol)
        Taxable(__taxed, __taxPoints, __burnPoints, __taxRecipient)
        Ownable(msg.sender)
    {
        require(__burnPoints > 0, "BurnPoints must be greater than 0 basis point");
        require(__taxPoints >= __burnPoints, "TaxPoints must be greater than BurnPoints");
        require(__taxPoints <= 1000, "TaxPoints must not exceed 1,000 basis points (10%)");
        require(__burnPoints <= 1000, "BurnPoints must not exceed 1,000 basis points (10%)");

        IRouter _router = IRouter(__routerAddress);
        address _pair = IFactory(_router.factory()).createPair(address(this), _router.WETH());
        router = _router;
        pair = _pair;

        _approve(address(this), address(router), type(uint).max);

        exemptTax(msg.sender);
        
        _mint(msg.sender, 1_000_000_000 * 10**decimals());
    }

    receive() external payable {}

    function enableTax() public onlyOwner {
        _taxOn();
    }

    function disableTax() public onlyOwner {
        _taxOff();
    }

    function updateTaxRecipient(address newRecipient) public onlyOwner {
        _updateTaxRecipient(newRecipient);
    }

    function exemptTax(address account) public onlyOwner {
        _exemptTax(account);
    }

    function revokeTaxExemption(address account) public onlyOwner {
        _revokeTaxExemption(account);
    }

    function exemptTaxFrom(address account) public onlyOwner {
        _exemptTaxFrom(account);
    }

    function revokeTaxExemptionFrom(address account) public onlyOwner {
        _revokeTaxExemptionFrom(account);
    }

    function exemptTaxTo(address account) public onlyOwner {
        _exemptTaxTo(account);
    }

    function revokeTaxExemptionTo(address account) public onlyOwner {
        _revokeTaxExemptionTo(account);
    }

    function rescueFund() public onlyOwner {
        payable(taxRecipient()).sendValue(address(this).balance);
    }

    function _update(address from, address to, uint amount)
        internal
        override
    {
        require(amount > 0, "Transfer amount must be greater than zero");
        
        if (_interlock || !isTaxed() || isTaxExempted(from) || isTaxExempted(to) || isTaxExemptedFrom(from) || isTaxExemptedTo(to) || (from != pair && to != pair)) {
            super._update(from, to, amount);
        } else {
            
            uint taxPortion = amount * taxPoints() / 10000;
            uint userPortion = amount - taxPortion;

            super._update(from, address(this), taxPortion); 

            if (from != pair) {
                liquify();
            }

            super._update(from, to, userPortion);
        }
    }

    function liquify() private lockTheSwap {
        uint contractTokenBalance = balanceOf(address(this));

        uint toBurn = contractTokenBalance * burnPoints() / taxPoints();
        uint toSwap = contractTokenBalance - toBurn;

        if (toSwap > 0) {
            swapTokensForEth(toSwap);
        }

        if (toBurn > 0) {
            super._update(address(this), address(0xdead), toBurn); 
        }
    }

    function swapTokensForEth(uint tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            taxRecipient(),
            block.timestamp
        );
    }
}