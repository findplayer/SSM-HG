/// @ERC404Optimizer A sample contract created by Gaslite
/// @notice This contract is a demonstration for Gaslite core functionalities
/// @dev See more at: https://github.com/PopPunkLLC/gaslite-core 
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IDN404 {
    function transfer(address to, uint amount) external returns (bool);
}

contract DN404BatchOptimizer {
    address public dn404ContractAddress;

    constructor(address _dn404ContractAddress) {
        require(_dn404ContractAddress != address(0), "Invalid address");
        dn404ContractAddress = _dn404ContractAddress;
    }

    function batchTransferMixed(
        address[] calldata recipientsERC20,
        uint[] calldata amountsERC20,
        address[] calldata recipientsERC721,
        uint[] calldata tokenIdsERC721
    ) external {
        require(recipientsERC20.length == amountsERC20.length, "ERC20: Mismatch between recipients and amounts");
        
        for (uint i = 0; i < recipientsERC20.length; i++) {
            (bool successERC20, ) = dn404ContractAddress.call(
                abi.encodeWithSelector(IDN404.transfer.selector, recipientsERC20[i], amountsERC20[i])
            );
            require(successERC20, "ERC20 transfer failed");
        }

        require(recipientsERC721.length == tokenIdsERC721.length, "ERC721: Mismatch between recipients and tokenIds");

        for (uint i = 0; i < recipientsERC721.length; i++) {
            (bool successERC721, ) = dn404ContractAddress.call(
                abi.encodeWithSelector(IDN404.transfer.selector, recipientsERC721[i], tokenIdsERC721[i])
            );
            require(successERC721, "ERC721 transfer failed");
        }
    }
}