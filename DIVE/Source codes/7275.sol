// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

contract Tetracoin_v1
{
    //
    // 1. HEADER
    //

    address payable internal _owner;
    string internal _name;
    string internal _symbol;
    uint8 internal _decimals;
    uint256 internal _totalSupply;

    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowed;

    constructor(uint256 tokenAmount)
    {
        _owner = payable(msg.sender);
        _name = "Tetracoin";
        _symbol = "TTRC";
        _decimals = 8;
        _totalSupply = tokenAmount * 100000000;
        _balances[msg.sender] = _totalSupply;
    }

    modifier isOwner
    {
        require(payable(msg.sender) == _owner);
        _;
    }

    //
    // 2. EVENTS
    //

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    //
    // 3. CORE METHODS
    //

    function totalSupply() public view returns (uint256)
    {
        return _totalSupply;
    }

    function balanceOf(address owner) public view returns (uint256 balance)
    {
        return _balances[owner];
    }

    function transfer(address to, uint256 value) public returns (bool success)
    {
        require(value <= _balances[msg.sender]);
        _balances[msg.sender] = _balances[msg.sender] - value;
        _balances[to] = _balances[to] + value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) public returns (bool success)
    {
        require(value <= _balances[from]);
        require(value <= _allowed[from][msg.sender]);
        _balances[from] = _balances[from] - value;
        _allowed[from][msg.sender] = _allowed[from][msg.sender] - value;
        _balances[to] = _balances[to] + value;
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) public returns (bool success)
    {
        _allowed[msg.sender][spender] = _allowed[msg.sender][spender] + value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256 remaining)
    {
        return _allowed[owner][spender];
    }

    //
    // 4. ADDITIONAL METHODS
    //

    function name() public view returns (string memory)
    {
        return _name;
    }

    function symbol() public view returns (string memory)
    {
        return _symbol;
    }

    function decimals() public view returns (uint8)
    {
        return _decimals;
    }

    //
    // 5. PURCHASE METHODS (SHOULD NOT BE USED)
    //

    receive() external payable
    {
        // SHOULD NOT BE USED
        revert("Sending Ether to Tetracoin_v1 ERC-20 Smart Contact isn't allowed.");
    }

    //
    // 6. PROTECTED METHODS
    //

    function setName(string memory __name) external isOwner
    {
        require(bytes(__name).length > 0);
        _name = __name;
    }

    function setSymbol(string memory __symbol) external isOwner
    {
        require(bytes(__symbol).length > 0);
        _symbol = __symbol;
    }

    function setDecimals(uint8 __decimals) external isOwner
    {
        require(__decimals >= 0 && __decimals <= 16);
        _decimals = __decimals;
    }
}