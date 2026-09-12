// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

interface IERC20Metadata is IERC20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
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

    function getMetadata(address token) public view returns (string memory name, string memory symbol, uint8 decimals) {
        IERC20Metadata _token = IERC20Metadata(token);
        name = _token.name();
        symbol = _token.symbol();
        decimals = _token.decimals();
        if(decimals == 0) {
            decimals = 1;
        }
    }
}