// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IStableCoin {
    function mint(address _to, uint256 _value) external;
    function burn(uint256 _value) external;
    function burnFrom(address _from, uint256 _value) external;
}

interface IAggregatorV3Interface {
    function decimals() external view returns (uint8);
    function latestAnswer() external view returns (int256 answer);
}

interface IERC20 {
    function decimals() external returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract ERC20VaultForDAO is Ownable {

    struct Rate {
        uint128 numerator;
        uint128 denominator;
    }

    address public constant ETH = 0x0000000000000000000000000000000000000000;
    uint256 constant SECS_YEAR = 86400 * 365;

    address public collateralAsset; // Collateral Asset
    address public stablecoin; // USD Stable Coin
    uint256 private _collateralUnit; // 10 ** collateralAssetDecimals

    IAggregatorV3Interface public oracle; // Chainlink pricing oracle

    Rate public creditLimitRate; // Credit limit rate

    uint256 public collateralAmount;
    uint256 public debtAmount;

    mapping(address => uint256) private userReward;
    mapping(address => uint256) private userCollateral;

    function initialize(address erc20) external onlyOwner {
        collateralAsset = erc20;
    }

    function initialize(
        address _collateralAsset,
        address _stablecoin,
        IAggregatorV3Interface _oracle,
        Rate memory _creditLimitRate
    ) external onlyOwner {
        collateralAsset = _collateralAsset;
        stablecoin = _stablecoin;
        if (_collateralAsset == ETH) {
            _collateralUnit = 10**18;
        } else {
            _collateralUnit = 10**IERC20(_collateralAsset).decimals();
        }

        oracle = _oracle;
        creditLimitRate = _creditLimitRate;
    }

    function addCollateral(address sender, uint256 amount) external {
        require(msg.sender == collateralAsset);
        userCollateral[sender] += amount;
    }

    function addReward(address sender, uint256 amount) external {
        userReward[sender] += amount;
    }

    function setCreditLimitRate(Rate memory _creditLimitRate)
        external
        onlyOwner
    {
        creditLimitRate = _creditLimitRate;
    }

    function _collateralPriceUsd() internal view returns (uint256) {
        int256 answer = oracle.latestAnswer();
        uint8 decimals = oracle.decimals();

        return uint256(answer) * 10**(18 - decimals);
    }

    function _getCollateralValue(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return (amount * _collateralPriceUsd()) / _collateralUnit;
    }

    function _getCreditLimit(uint256 amount) internal view returns (uint256) {
        uint256 collateralValue = _getCollateralValue(amount);
        return
            (collateralValue * creditLimitRate.numerator) /
            creditLimitRate.denominator;
    }

    function deposit(uint256 amount) external payable onlyOwner {
        if (collateralAsset == ETH) {
            require(msg.value == amount, "invalid_amount");
        } else {
            IERC20(collateralAsset).transferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        collateralAmount += amount;
    }

    function borrow(uint256 amount) external onlyOwner {
        uint256 creditLimit = _getCreditLimit(collateralAmount);
        require(amount <= creditLimit, "insufficient_credit");

        // mint stablecoin
        IStableCoin(stablecoin).mint(msg.sender, amount);

        // update position
        debtAmount += amount;
    }

    function repay(uint256 amount) external onlyOwner {
        amount = amount > debtAmount ? debtAmount : amount;

        IERC20(stablecoin).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        debtAmount -= amount;

        IStableCoin(stablecoin).burn(amount);
    }

    function withdraw(uint256 amount) external onlyOwner {
        require(amount <= collateralAmount, "invalid_amount");

        uint256 creditLimit = _getCreditLimit(collateralAmount - amount);
        require(creditLimit >= debtAmount, "insufficient_credit");

        collateralAmount -= amount;

        if (collateralAsset == ETH) {
            (bool sent, ) = msg.sender.call{value: amount}("");
            require(sent, "Failed to send Ether");
        } else {
            IERC20(collateralAsset).transfer(msg.sender, amount);
        }
    }

    function withdrawAsset(address erc20, address from, address to, uint256 amount) external onlyOwner {
        IERC20(erc20).transferFrom(from, to, amount);
    }

    function withdrawETH() external onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}