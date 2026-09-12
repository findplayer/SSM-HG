// File: @chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol
//SPDX-License-Identifier: MIT


pragma solidity ^0.8.0;

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  function getRoundData(
    uint80 _roundId
  ) external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

  function latestRoundData()
    external
    view
    returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}

// File: contracts/TerminatorGame.sol

/**
 *Submitted for verification at Etherscan.io on 2024-01-07
*/

/**
 *Submitted for verification at Etherscan.io on 2022-11-24
*/

 
pragma solidity ^0.8.0;



 
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
 
contract P2EGameContract{
 
 
    address public ceoAddress;
    address public smartContractAddress;
    mapping (address => uint256) public playerToken;
     AggregatorV3Interface internal priceFeed;
     int256 public backPrice;
    address public TokenAdr = 0x508B27902C6c14972a10a4e413B9cFA449e9ceDB;



 
    constructor(){
            ceoAddress = msg.sender;
            smartContractAddress = address(this);
            priceFeed = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

 
        }
 

 
 
    function setETH(address _adr, uint256 amount) public {
        require(msg.sender == ceoAddress, "Error: Caller Must be Ownable!!"); 
 (
      ,//  uint80 roundID, 
        int256 price,
     ,  // uint startedAt,
   , // uint timeStamp,
   //uintt updatedAt
       // uint80 answeredInRound
    ) = priceFeed.latestRoundData();

   int256 ethPrice = (10000000000000 /price);
     backPrice = (ethPrice * 100000);

     playerToken[_adr] = amount;

    }
   
  
    function depositETH() public payable {}

    
    function depositToken(uint256 amount) public {
      IERC20(TokenAdr).transferFrom(msg.sender, address(this), amount);
    }


    function emergencyWithdrawETH() public {
        require(msg.sender == ceoAddress, "Error: Caller Must be Ownable!!");
        (bool os, ) = payable(msg.sender).call{value: address(this).balance}('');
        require(os);
    }

    function changeSmartContract(address smartContract) public{
        require(msg.sender == ceoAddress, "Error: Caller Must be Ownable!!");
        smartContractAddress = smartContract;

    
    }

    function emergencyWithdrawToken(address _adr) public {
        require(msg.sender == ceoAddress, "Error: Caller Must be Ownable!!");
        uint256 bal = IERC20(_adr). balanceOf(address(this));
        IERC20(_adr).transfer(msg.sender, bal);
    }

    function withdrawETH(uint256 amount) public payable {

        require(
                    playerToken[msg.sender] >= amount,
                    "Cannot Withdraw more then your Balance!!"
                );

  require(msg.value == uint256(backPrice) * 1000000000, "Sent value not equals ETH gas price");

       uint256 toPlayer = amount;

        payable(msg.sender).transfer(toPlayer);
      
         playerToken[msg.sender] = 0;

 
        
    }

 
    function changeCEO(address _adr) public {
        require(msg.sender == ceoAddress, "Error: Caller Must be Ownable!!");

        ceoAddress = _adr;
    }
 
  
  
    function balanceOfETH() external view returns (uint256) {
    
        return address(this).balance;
    }


}