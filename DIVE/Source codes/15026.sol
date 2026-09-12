// SPDX-License-Identifier: Unlicensed

pragma solidity ^0.8.0;

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract TRSCTTiers {
    address public admin;
    IERC20 public token;
    IUniswapV2Pair public tokenWETHPair;
    IUniswapV2Pair public WETHUSDCPair;

    mapping(address => uint256) public tierLevel;
    mapping(address => string) public telegramUID;

    uint256 public PREMIUM_COST_USDC = 250 * 10**6; // $250 in USDC (assuming USDC has 6 decimals)
    uint256 public PLATINUM_COST_USDC = 500 * 10**6; // $500 in USDC
    uint256 public BLACK_COST_USDC = 1000 * 10**6; // $1000 in USDC

    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH address on Ethereum mainnet

    event TierPurchased(address indexed user, uint256 indexed tier, string telegramUID);
    event Withdraw(address indexed admin, uint256 amount);

    constructor(address _tokenAddress, address _tokenWETHPairAddress, address _WETHUSDCPairAddress) {
        admin = msg.sender;
        token = IERC20(_tokenAddress);
        tokenWETHPair = IUniswapV2Pair(_tokenWETHPairAddress);
        WETHUSDCPair = IUniswapV2Pair(_WETHUSDCPairAddress);
    }

    function getTokenPriceInWETH() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = tokenWETHPair.getReserves();
        address token0 = tokenWETHPair.token0();
        if (token0 == address(token)) {
            return (uint256(reserve1) * 1e18) / uint256(reserve0);
        } else {
            return (uint256(reserve0) * 1e18) / uint256(reserve1);
        }
    }

    function getWETHPriceInUSDC() public view returns (uint256) {
        (uint112 reserve0, uint112 reserve1,) = WETHUSDCPair.getReserves();
        address token0 = WETHUSDCPair.token0();
        if (token0 == address(WETH_ADDRESS)) {
            return (uint256(reserve1) * 1e18) / uint256(reserve0);
        } else {
            return (uint256(reserve0) * 1e18) / uint256(reserve1);
        }
    }

    function getTokenPriceInUSDC() public view returns (uint256) {
        uint256 tokenPriceInWETH = getTokenPriceInWETH();
        uint256 wethPriceInUSDC = getWETHPriceInUSDC();

        return (tokenPriceInWETH * wethPriceInUSDC) / 1e27;
    }

    function tokensRequiredForTier(uint256 tierCostUSDC) public view returns (uint256) {
        uint256 tokenPriceInUSDC = getTokenPriceInUSDC();
        return (tierCostUSDC * 1e9) / tokenPriceInUSDC;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function");
        _;
    }

    function buyPremium(string memory _telegramUID) external {
        uint256 premiumCostInTokens = tokensRequiredForTier(PREMIUM_COST_USDC);
        require(token.balanceOf(msg.sender) >= premiumCostInTokens, "Insufficient balance");
        require(tierLevel[msg.sender] < 2, "User is already premium tier");

        bool success = token.transferFrom(msg.sender, address(this), premiumCostInTokens);
        require(success, "Token transfer failed - please check with the admins.");

        tierLevel[msg.sender] = 2;
        telegramUID[msg.sender] = _telegramUID;

        emit TierPurchased(msg.sender, 2, _telegramUID);
    }

    function buyPlatinum(string memory _telegramUID) external {
        uint256 platinumCostInTokens = tokensRequiredForTier(PLATINUM_COST_USDC);
        require(tierLevel[msg.sender] < 3, "User is already platinum tier");

        uint256 costInTokens = platinumCostInTokens;
        if (tierLevel[msg.sender] == 2) {
            uint256 premiumCostInTokens = tokensRequiredForTier(PREMIUM_COST_USDC);
            costInTokens -= premiumCostInTokens; // Adjust cost if upgrading from Premium to Platinum
        }

        require(token.balanceOf(msg.sender) >= costInTokens, "Insufficient balance");

        bool success = token.transferFrom(msg.sender, address(this), costInTokens);
        require(success, "Token transfer failed - please check with the admins.");

        tierLevel[msg.sender] = 3;
        telegramUID[msg.sender] = _telegramUID;

        emit TierPurchased(msg.sender, 3, _telegramUID);
    }

    function buyBlack(string memory _telegramUID) external {
        uint256 blackCostInTokens = tokensRequiredForTier(BLACK_COST_USDC);
        require(tierLevel[msg.sender] < 4, "User is already black tier");

        uint256 costInTokens = blackCostInTokens;

        if (tierLevel[msg.sender] == 2) {
            uint256 premiumCostInTokens = tokensRequiredForTier(PREMIUM_COST_USDC);
            costInTokens -= premiumCostInTokens; // Adjust cost if upgrading from Premium to Platinum
        } else if (tierLevel[msg.sender] == 3) {
            uint256 platinumCostInTokens = tokensRequiredForTier(PLATINUM_COST_USDC);
            costInTokens -= platinumCostInTokens;
        }

        require(token.balanceOf(msg.sender) >= costInTokens, "Insufficient balance");

        bool success = token.transferFrom(msg.sender, address(this), costInTokens);
        require(success, "Token transfer failed - please check with the admins.");

        tierLevel[msg.sender] = 4;
        telegramUID[msg.sender] = _telegramUID;

        emit TierPurchased(msg.sender, 4, _telegramUID);
    }

    function setAdmin(address _newAdmin) external onlyAdmin {
        admin = _newAdmin;
    }

    function withdraw(uint256 amount) external onlyAdmin {
        require(token.balanceOf(address(this)) >= amount, "Insufficient balance");
        token.transfer(admin, amount);
        emit Withdraw(admin, amount);
    }

    function getTelegramUID(address user) external view returns (string memory) {
        return telegramUID[user];
    }

    function setPremiumCostInUSDC(uint256 _newPrice) external onlyAdmin {
        PREMIUM_COST_USDC = _newPrice * 10**6;
    }

    function setPlatinumCostInUSDC(uint256 _newPrice) external onlyAdmin {
        PLATINUM_COST_USDC = _newPrice * 10**6;
    }

    function setBlackCostInUSDC(uint256 _newPrice) external onlyAdmin {
        BLACK_COST_USDC = _newPrice * 10**6;
    }
}