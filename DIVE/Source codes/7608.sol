// SPDX-License-Identifier: MIT
/*

Happy INU will be a gaming platform where game developers are rewarded for quality content and players can win prizes in weekly competitions.

JOIN US ON TELEGRAM: https://t.me/hpyinu_portal

Find out more about HpyINU:
website: https://www.happyinu.games/
twitter: https://twitter.com/hpyinu
medium: https://medium.com/@hpyinu

Happy's Quest: https://chipper-pika-c64478.netlify.app/
*/
pragma solidity 0.8.19;




contract HAPPYINU {
    function name() public pure returns (string memory) {
        return "Happy Inu";
    }
    function symbol() public pure returns (string memory) {
        return "HpyINU";
    }
    function decimals() public pure returns (uint8) {
        return 0;
    }
    function totalSupply() public pure returns (uint256) {
        return 100000000;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function balanceOf(address account) public view returns (uint256) {
        return 0;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function transfer(address recipient, uint256 amount) public returns (bool) {
        return true;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function allowance(address owner, address spender) public view  returns (uint256) {
        return 0;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function approve(address spender, uint256 amount) public  returns (bool) {
        return true;
    }
    // this is a dummy contract, actual implementation will be added in official one
    function transferFrom(address sender, address recipient, uint256 amount) public  returns (bool) {
        return true;
    }
    receive() external payable {}
}