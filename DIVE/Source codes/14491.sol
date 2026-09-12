// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

// A public, free (except gas) public registry
//
// Ethereum public keys should be 33 bytes for compressed keys or 65 bytes
// for uncompressed keys. A 64-byte key is ok assuming clients will prepend the
// leading '04' byte.
//
// WARN: this contract can accept eth but does not handle tokens

contract EphPubkeyRegistry {

  // low-cost way to publish but cannot be read by other contracts
  event Registered( bytes pubkey );

  address payable _owner;

  modifier isOwner {
    if (msg.sender != _owner) {
      revert( "owner only" );
    }
    _;
  }

  // 353719 gas used in test
  constructor() {
    _owner = payable(msg.sender);
  }

  // 24624 gas for a 33-byte value, 25398 for 65 bytes gas used in test
  function register( bytes calldata pubkey ) external {
    emit Registered( pubkey );
  }

  // 27135 gas in test
  function chown( address payable newown ) external isOwner {
    _owner = newown;
  }

  // 30388 gas in test
  function sweep() external isOwner {
    _owner.transfer( address(this).balance );
  }

  // 21055 gas to send eth to this contract (hint) in test
  receive() external payable {}

  fallback() external payable {}
}