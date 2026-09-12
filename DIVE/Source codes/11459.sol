// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// Telegram: https://t.me/TheInfiniteGardenETH
// Website: https://infinitegardeneth.com
// Twitter: https://twitter.com/ETHgardenIGETH

contract ERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    address public owner;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public maxTokensPerWallet = 2000000 * (10 ** uint256(decimals));

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor(string memory _name, string memory _symbol, uint256 _totalSupply, address _owner) {
        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply * (10 ** uint256(decimals));
        owner = _owner;
        balanceOf[_owner] = totalSupply;
        emit Transfer(address(0), _owner, totalSupply);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    function transfer(address _to, uint256 _value) external returns (bool success) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    function _transfer(address _from, address _to, uint256 _value) internal {
        require(_to != address(0), "Invalid transfer to the zero address");
        require(balanceOf[_from] >= _value, "Insufficient balance");
        require(balanceOf[_to] + _value <= maxTokensPerWallet, "Recipient wallet token limit exceeded");

        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) external returns (bool success) {
        require(_value <= allowance[_from][msg.sender], "Allowance exceeded");
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }

    function approve(address _spender, uint256 _value) external returns (bool success) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function increaseAllowance(address _spender, uint256 _addedValue) external returns (bool success) {
        allowance[msg.sender][_spender] += _addedValue;
        emit Approval(msg.sender, _spender, allowance[msg.sender][_spender]);
        return true;
    }

    function decreaseAllowance(address _spender, uint256 _subtractedValue) external returns (bool success) {
        uint256 currentAllowance = allowance[msg.sender][_spender];
        require(_subtractedValue <= currentAllowance, "Decreased allowance below zero");
        allowance[msg.sender][_spender] -= _subtractedValue;
        emit Approval(msg.sender, _spender, allowance[msg.sender][_spender]);
        return true;
    }

    function setMaxTokensPerWallet(uint256 _maxTokensPerWallet) external onlyOwner {
        require(_maxTokensPerWallet <= 2000000, "Cannot exceed 2000000 tokens per wallet");
        maxTokensPerWallet = _maxTokensPerWallet * (10 ** uint256(decimals));
    }

    function renounceOwnership() external onlyOwner {
        emit OwnershipTransferred(owner, address(0));
        owner = address(0);
    }
}