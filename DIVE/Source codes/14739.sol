// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function decimals() external view returns (uint8);
}

contract HelperContract {
    function getBalance(address token, address user) public view returns (uint256) {
        return IERC20(token).balanceOf(user);
    }

    function getBalances(address[] memory tokens, address[] memory users) public view returns (uint256[] memory) {
        uint256 count = tokens.length;
        require(count == users.length, "tokens.length != users.length");
        uint256[] memory balances = new uint256[](count);
        for(uint i = 0; i < count; i ++) {
            balances[i] = getBalance(tokens[i], users[i]);
        }
        return balances;
    }

    function getDecimals(address token) public view returns (uint8) {
        uint8 decimals = IERC20(token).decimals();
        if(decimals == 0) {
            decimals = 1;
        }
        return decimals;
    }

}