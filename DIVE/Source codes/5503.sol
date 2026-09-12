// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract EthMultiSend {
	address private immutable owner;
	constructor() {
		owner = msg.sender;
	}
	
	receive() external payable {}

	function multiSendEth(string calldata note, address[] calldata addresses, uint256[] calldata weiAmounts) external payable {
		require(addresses.length == weiAmounts.length);

		uint256 totalAmount = 0;
		for(uint i=0; i < addresses.length; i++){
            totalAmount += weiAmounts[i] ;
        }
        require(msg.value >= totalAmount);

		for(uint i=0; i < addresses.length; i++){
            payable(addresses[i]).transfer(weiAmounts[i]);
        }
	}

	function recoverETH() external {
		require(msg.sender == owner);
		require(address(this).balance>0);
		payable(owner).transfer(address(this).balance);
	}
}