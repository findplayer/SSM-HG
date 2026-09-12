// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface AutomationCompatibleInterface {
    function checkUpkeep(
        bytes calldata checkData
    ) external returns (bool upkeepNeeded, bytes memory performData);

    function performUpkeep(bytes calldata performData) external;
}

interface IRebalancer {
    function getToken0Address() external view returns (address);

    function getToken1Address() external view returns (address);

    function get24HourTotals() external view returns (uint256, uint256);

    function get7DayTotals() external view returns (uint256, uint256);

    function getPoolAddress() external view returns (address);

    function getEthDeposited() external view returns (uint256);

    function getToken0Collected() external view returns (uint256);

    function getToken1Collected() external view returns (uint256);

    function getTokenID() external view returns (uint256);

    function checkUpkeep(
        bytes calldata
    ) external view returns (bool, bytes memory);

    function performUpkeep(bytes calldata performData) external;

    function transferOwnership(address newOwner) external;
}

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);

    function version() external view returns (uint256);

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);
}

contract RebalancerFeed is AutomationCompatibleInterface {
    AggregatorV3Interface internal BTCPriceFeed;
    AggregatorV3Interface internal ETHPriceFeed;
    AggregatorV3Interface internal BNBPriceFeed;
    AggregatorV3Interface internal USDTPriceFeed;
    AggregatorV3Interface internal LINKPriceFeed;
    AggregatorV3Interface internal AVAXPriceFeed;
    AggregatorV3Interface internal SOLPriceFeed;
    AggregatorV3Interface internal MATICPriceFeed;

    address public owner;
    IRebalancer[] public deployedRebalancers;
    uint256 private batchSize = 5;
    uint256 private lastIndex = 0;

    event ChildAdded(address indexed childAddress);
    event BatchSizeUpdated(uint256 newBatchSize);
    event SweepedERC20(address token, uint256 amount);
    event SweepedNative(uint256 amount);
    event ChildRemoved(address indexed childAddress);
    event PriceFeedsUpdated();

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setPriceFeeds(
        address _btc,
        address _eth,
        address _bnb,
        address _usdt,
        address _link,
        address _avax,
        address _sol,
        address _matic
    ) external onlyOwner {
        require(
            _btc != address(0) &&
                _eth != address(0) &&
                _bnb != address(0) &&
                _usdt != address(0) &&
                _link != address(0) &&
                _avax != address(0) &&
                _sol != address(0) &&
                _matic != address(0),
            "Invalid address"
        );

        BTCPriceFeed = AggregatorV3Interface(_btc);
        ETHPriceFeed = AggregatorV3Interface(_eth);
        BNBPriceFeed = AggregatorV3Interface(_bnb);
        USDTPriceFeed = AggregatorV3Interface(_usdt);
        LINKPriceFeed = AggregatorV3Interface(_link);
        AVAXPriceFeed = AggregatorV3Interface(_avax);
        SOLPriceFeed = AggregatorV3Interface(_sol);
        MATICPriceFeed = AggregatorV3Interface(_matic);

        emit PriceFeedsUpdated();
    }

    function getBTCPrice() public view returns (int) {
        (, int BTCprice, , , ) = BTCPriceFeed.latestRoundData();
        return BTCprice;
    }

    function getETHPrice() public view returns (int) {
        (, int ETHprice, , , ) = ETHPriceFeed.latestRoundData();
        return ETHprice;
    }

    function getBNBPrice() public view returns (int) {
        (, int BNBprice, , , ) = BNBPriceFeed.latestRoundData();
        return BNBprice;
    }

    function getUSDTPrice() public view returns (int) {
        (, int USDTprice, , , ) = USDTPriceFeed.latestRoundData();
        return USDTprice;
    }

    function getLINKPrice() public view returns (int) {
        (, int LINKprice, , , ) = LINKPriceFeed.latestRoundData();
        return LINKprice;
    }

    function getAVAXPrice() public view returns (int) {
        (, int AVAXprice, , , ) = AVAXPriceFeed.latestRoundData();
        return AVAXprice;
    }

    function getSOLPrice() public view returns (int) {
        (, int SOLprice, , , ) = SOLPriceFeed.latestRoundData();
        return SOLprice;
    }

    function getMATICPrice() public view returns (int) {
        (, int MATICprice, , , ) = MATICPriceFeed.latestRoundData();
        return MATICprice;
    }

    function getAllRebalancerAddresses()
        public
        view
        returns (IRebalancer[] memory)
    {
        return deployedRebalancers;
    }

    function getTokenInfo(
        address rebalancer
    ) public view returns (address, address) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        IRebalancer instance = IRebalancer(rebalancer);
        return (instance.getToken0Address(), instance.getToken1Address());
    }

    function get24HourTotals(
        address rebalancer
    ) public view returns (uint256, uint256) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        return IRebalancer(rebalancer).get24HourTotals();
    }

    function get7DayTotals(
        address rebalancer
    ) public view returns (uint256, uint256) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        return IRebalancer(rebalancer).get7DayTotals();
    }

    function getPoolAddress(address rebalancer) public view returns (address) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        return IRebalancer(rebalancer).getPoolAddress();
    }

    function getEthDeposited(address rebalancer) public view returns (uint256) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        return IRebalancer(rebalancer).getEthDeposited();
    }

    function getToken0Collected(
        address rebalancer
    ) public view returns (uint256) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        return IRebalancer(rebalancer).getToken0Collected();
    }

    function getToken1Collected(
        address rebalancer
    ) public view returns (uint256) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        return IRebalancer(rebalancer).getToken1Collected();
    }

    function getTokenID(address rebalancer) public view returns (uint256) {
        require(isContract(rebalancer), "Address is not a deployed rebalancer");
        return IRebalancer(rebalancer).getTokenID();
    }

    function addChild(address childAddress) public onlyOwner {
        require(childAddress != address(0), "Invalid address");
        require(isContract(childAddress), "Address must be a contract");
        require(!isAlreadyAdded(childAddress), "Address already added");

        deployedRebalancers.push(IRebalancer(childAddress));
        emit ChildAdded(childAddress);
    }

    function removeChild(address childAddress) public onlyOwner {
        require(isContract(childAddress), "Address must be a contract");
        require(isAlreadyAdded(childAddress), "Address not found");

        int256 indexToRemove = -1;
        for (uint256 i = 0; i < deployedRebalancers.length; i++) {
            if (address(deployedRebalancers[i]) == childAddress) {
                indexToRemove = int256(i);
                break;
            }
        }

        require(indexToRemove >= 0, "Child contract not found");
        deployedRebalancers[uint256(indexToRemove)] = deployedRebalancers[
            deployedRebalancers.length - 1
        ];
        deployedRebalancers.pop();

        emit ChildRemoved(childAddress);
    }

    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    function isAlreadyAdded(address childAddress) internal view returns (bool) {
        for (uint256 i = 0; i < deployedRebalancers.length; i++) {
            if (address(deployedRebalancers[i]) == childAddress) {
                return true;
            }
        }
        return false;
    }

    function sweepERC20(address _tokenAddress) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        uint256 amount = token.balanceOf(address(this));
        require(amount > 0, "No tokens to sweep");
        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit SweepedERC20(_tokenAddress, amount);
    }

    function sweepNative() external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No native currency to sweep");
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        emit SweepedNative(amount);
    }

    function setBatchSize(uint256 _newBatchSize) public onlyOwner {
        require(_newBatchSize > 0, "Batch size must be greater than 0");
        batchSize = _newBatchSize;
        emit BatchSizeUpdated(_newBatchSize);
    }

    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        address[] memory contractsRequiringUpkeep;
        uint count = 0;

        for (uint256 i = 0; i < deployedRebalancers.length; i++) {
            (bool childNeedsUpkeep, ) = deployedRebalancers[i].checkUpkeep("");
            if (childNeedsUpkeep) {
                count++;
            }
        }

        contractsRequiringUpkeep = new address[](count);

        uint index = 0;
        for (uint256 i = 0; i < deployedRebalancers.length; i++) {
            (bool childNeedsUpkeep, ) = deployedRebalancers[i].checkUpkeep("");
            if (childNeedsUpkeep) {
                contractsRequiringUpkeep[index] = address(
                    deployedRebalancers[i]
                );
                index++;
                upkeepNeeded = true;
            }
        }

        performData = abi.encode(contractsRequiringUpkeep);
    }

    function performUpkeep(bytes calldata performData) external override {
        address[] memory contractsNeedingUpkeep = abi.decode(
            performData,
            (address[])
        );
        uint256 processedCount = 0;

        for (
            uint256 i = 0;
            i < contractsNeedingUpkeep.length && processedCount < batchSize;
            i++
        ) {
            IRebalancer rebalancer = IRebalancer(contractsNeedingUpkeep[i]);

            rebalancer.performUpkeep("0x");
            processedCount++;
        }
    }
}