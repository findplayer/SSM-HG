pragma solidity ^0.8.0;

// Import ERC20 interface
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}

contract TokenBalanceResolver {
    struct TokenBalance {
        uint256 balance;
        bool success;
    }

    struct UserTokenBalances {
        address user;
        TokenBalance[] balances;
    }

    address private constant ETHER_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function getBalances(address user, address[] memory tokenAddresses) public returns (UserTokenBalances memory) {
        return UserTokenBalances(user, _getBalances(user, tokenAddresses));
    }

    function getBalancesForMultipleUsers(address[] memory users, address[] memory tokenAddresses) public returns (UserTokenBalances[] memory) {
        UserTokenBalances[] memory allUserBalances = new UserTokenBalances[](users.length);
        
        for (uint256 i = 0; i < users.length; i++) {
            allUserBalances[i].user = users[i];
            allUserBalances[i].balances = _getBalances(users[i], tokenAddresses);
        }

        return allUserBalances;
    }

    function _getBalances(address user, address[] memory tokenAddresses) private returns (TokenBalance[] memory) {
        TokenBalance[] memory balances = new TokenBalance[](tokenAddresses.length);

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            if (tokenAddresses[i] == ETHER_ADDRESS) {
                balances[i].balance = user.balance;
                balances[i].success = true;
            } else {
                // Create a low-level call to the balanceOf function
                bytes memory callData = abi.encodeWithSelector(IERC20(tokenAddresses[i]).balanceOf.selector, user);

                // Make the call and catch any revert/invalid operation exceptions
                (bool success, bytes memory result) = tokenAddresses[i].call(callData);

                if (success) {
                    // Decode the result and store it in the balances array
                    balances[i].balance = abi.decode(result, (uint256));
                    balances[i].success = true;
                } else {
                    // If an error occurred or the call failed, store a balance and success flag as false
                    balances[i].balance = 0;
                    balances[i].success = false;
                }
            }
        }

        return balances;
    }
}