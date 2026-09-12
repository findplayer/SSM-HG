// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract PaymentSplitter {
    address payable public wallet90Percent = payable(0x049282b2133578f0484353394f7ff5a36d63979F);
    address payable public wallet10Percent = payable(0xa64BE6421aab00F534F95AC34Cf3bdC561BA559b);

    receive() external payable {
        uint256 amountToWallet90Percent = (msg.value * 90) / 100;
        uint256 amountToWallet10Percent = msg.value - amountToWallet90Percent;
        wallet90Percent.transfer(amountToWallet90Percent);
        wallet10Percent.transfer(amountToWallet10Percent);
    }
}