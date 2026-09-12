// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

contract Kick2 {
    mapping(address => uint) public balances;

    // 送金されたETHを指定のアドレスの残高に加算して保管する
    function deposit(address _to) external payable {
        require(msg.value > 0, "Send ETH to deposit");
        balances[_to] += msg.value;
    }

    // 実行者のアドレスに保管されてるETHを全て実行者に送る
    function withdraw() external {
        uint balance = balances[msg.sender];
        require(balance > 0, "No ETH to withdraw");
        balances[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
    }
}