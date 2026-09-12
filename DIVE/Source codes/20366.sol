/// @ERC404Optimizer A sample contract created by Gaslite
/// @notice This contract is a demonstration for Gaslite core functionalities
/// @dev See more at: https://github.com/PopPunkLLC/gaslite-core 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDN404 {
    function transfer(address to, uint amount) external returns (bool);
    function approve(address spender, uint amount) external returns (bool);
}

contract DN404Optimizer {
    address public dn404ContractAddress;

    constructor(address _dn404ContractAddress) {
        require(_dn404ContractAddress != address(0), "Invalid address");
        dn404ContractAddress = _dn404ContractAddress;
    }

    function batchTransferERC20(address[] calldata recipients, uint[] calldata amounts) external {
        require(recipients.length == amounts.length, "Mismatch between recipients and amounts");
        
        for (uint i = 0; i < recipients.length; i++) {
            (bool success, ) = dn404ContractAddress.call(
                abi.encodeWithSelector(IDN404.transfer.selector, recipients[i], amounts[i])
            );
            require(success, "ERC20 transfer failed");
        }
    }

    function batchTransferERC721(address[] calldata recipients, uint[] calldata tokenIds) external {
        require(recipients.length == tokenIds.length, "Mismatch between recipients and tokenIds");
        
        for (uint i = 0; i < recipients.length; i++) {
            (bool success, ) = dn404ContractAddress.call(
                abi.encodeWithSelector(IDN404.transfer.selector, recipients[i], tokenIds[i])
            );
            require(success, "ERC721 transfer failed");
        }
    }

    function batchApproveERC20(address spender, uint[] calldata amounts) external {
        for (uint i = 0; i < amounts.length; i++) {
            (bool success, ) = dn404ContractAddress.call(
                abi.encodeWithSelector(IDN404.approve.selector, spender, amounts[i])
            );
            require(success, "ERC20 approve failed");
        }
    }
}