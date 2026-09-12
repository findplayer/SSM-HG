// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IToken {
  function mint(address to, uint amount) external;
  function burn(address owner, uint amount) external;
}

contract BridgeBase {
  address public admin;
  IToken public token;
  uint public nonce;
  mapping(uint => bool) public processedNonces;

  enum Step { Burn, Mint }
  event Transfer(
    address from,
    address to,
    uint amount,
    uint date,
    uint nonce,
    Step indexed step,
    uint256 chainId
  );

  constructor(address payable _address , address _token) {
    admin = _address;
    token = IToken(_token);
  }

  function burn(address to, uint amount,uint256 chainId) external {
    token.burn(msg.sender, amount);
    emit Transfer(
      msg.sender,
      to,
      amount,
      block.timestamp,
      nonce,
      Step.Burn,
      chainId
    );
    nonce++;
  }

  function mint(address to, uint amount, uint otherChainNonce,uint256 chainId) external {
    require(msg.sender == admin, 'only admin');
    // require(processedNonces[otherChainNonce] == false, 'transfer already processed');
    processedNonces[otherChainNonce] = true;
    token.mint(to, amount);
    emit Transfer(
      msg.sender,
      to,
      amount,
      block.timestamp,
      otherChainNonce,
      Step.Mint,
      chainId
    );
  }
}

contract BridgeEth is BridgeBase {
  constructor(address payable _address , address token) BridgeBase(_address, token) {}
}