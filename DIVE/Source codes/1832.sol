// SPDX-License-Identifier: MIT

pragma solidity =0.8.9;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

contract VirtualVersionsErc20Upgrader {
    address public constant BLACK_HOLE_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    address public admin_;

    address public oldToken_;
    address public newToken_;

    function version() external pure returns (string memory) { return "VirtualVersionsErc20Upgrader v1"; }

    constructor(address _admin, address _oldToken, address _newToken) {
        require(_admin != address(0), "TA-5: zero admin address");
        admin_ = _admin;

        require(_oldToken != address(0) && _newToken != address(0), "TA-1: zero token address");
        oldToken_ = _oldToken;
        newToken_ = _newToken;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin_, "TA-4: auth failed");
        _;
    }

    function withdraw(address _token, address _recipient, uint256 _amount) external onlyAdmin {
        require(IERC20(_token).transfer(_recipient, _amount), "TA-6: transfer failed");
    }

    function upgrade(address _recipient, uint256 _amount) external {
        require(_amount != 0, "TA-2: zero token amount");
        require(_recipient != address(0), "TA-3: zero recipient address");

        require(IERC20(oldToken_).transferFrom(msg.sender, BLACK_HOLE_ADDRESS, _amount), "TA-7: burn failed");
        require(IERC20(newToken_).transfer(_recipient, _amount), "TA-8: transfer failed");
    }
}