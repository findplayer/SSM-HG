// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

//ERC Token Standard #20 Interface
interface ERC20Interface {
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint balance);
    function transfer(address recipient, uint amount) external returns (bool success);
    function allowance(address owner, address spender) external view returns (uint remaining);
    function approve(address spender, uint amount) external returns (bool success);
    function transferFrom(address sender, address recipient, uint amount) external returns (bool success);
    function burn(uint amount) external;

    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

//Actual token contract
contract PunkCoin is ERC20Interface {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint public _totalSupply;

    mapping (address => uint) balances;
    mapping (address => mapping (address => uint)) allowed;

    constructor() {
        name = "PunkCoin";
        symbol = "Punks";
        decimals = 18;
        _totalSupply = 2000000000 * 10**decimals;
        balances[0xCD69Ba0D65193918127Df9fcF656023E80021570] = _totalSupply;
        emit Transfer(address(0), 0xCD69Ba0D65193918127Df9fcF656023E80021570, _totalSupply);
    }

    function totalSupply() public view override returns (uint) {
        return _totalSupply - balances[address(0)];
    }

    function balanceOf(address account) public view override returns (uint balance) {
        return balances[account];
    }

    function transfer(address recipient, uint amount) public override returns (bool success) {
        balances[msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint amount) public override returns (bool success) {
        allowed[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint amount) public override returns (bool success) {
        balances[sender] -= amount;
        allowed[sender][msg.sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint remaining) {
        return allowed[owner][spender];
    }
   
    function burn(uint amount) public override {
        require(msg.sender != address(0), "PunkCoin: burn from the zero address");
        require(balances[msg.sender] >= amount, "PunkCoin: burn amount exceeds balance");
    
        balances[msg.sender] -= amount;
        _totalSupply -= amount;
        emit Transfer(msg.sender, address(0), amount);
    
    }
    
}