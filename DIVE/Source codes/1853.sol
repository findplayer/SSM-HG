// SPDX-License-Identifier: MIT
/**

Turn inspiration into reality - Create, collaborate, master, distribute, and promote your music all in one place.

Telegram: https://t.me/MusicAIEth
Twitter: https://twitter.com/MusicAITech
Medium: https://medium.com/@MusicAiTech/music-ai-turn-inspiration-into-reality-7741893dfd09
Website: https://www.musicai.media/

**/
pragma solidity 0.8.19;

// this is a dummy contract, actual implementation will be added in official one
contract MUSAI {
    function name() public pure returns (string memory) {return "MUSIC TECH";}
    function symbol() public pure returns (string memory) {return "MUSAI";}
    function decimals() public pure returns (uint8) {return 0;}
    function totalSupply() public pure returns (uint256) {return 100000000;}
    function balanceOf(address account) public view returns (uint256) {return 0;}
    function transfer(address recipient, uint256 amount) public returns (bool) {return true;}
    function allowance(address owner, address spender) public view  returns (uint256) {return 0;}
    function approve(address spender, uint256 amount) public  returns (bool) {return true;}
    function transferFrom(address sender, address recipient, uint256 amount) public  returns (bool) {return true;}
    receive() external payable {}
}