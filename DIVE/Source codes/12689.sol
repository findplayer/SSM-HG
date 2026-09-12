// SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

interface Router {
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);
   
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract CiaMail is Ownable {
    Router public router;
    IERC20 public cia;
    address public weth;
    address public usdt;
    address public feeAddress;
    uint256 public fee = 200e6; // 200 USDT
    mapping(address => uint256) public balances;

    event Buy(address indexed sender, uint256 amount);

    constructor(address _router, address _cia, address _weth, address _usdt, address _feeAddress) {
        router = Router(_router);
        cia = IERC20(_cia);
        weth = _weth;
        usdt = _usdt;
        feeAddress = _feeAddress;
    }

    function claimStuckTokens(address _token, address _to) external onlyOwner {
        require(_to != address(0), "Mail: address is the zero address");
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "Mail: no balance");
        require(token.transfer(_to, balance), "Mail: transfer failed");
    }

    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "Mail: router is the zero address");
        router = Router(_router);
    }

    function setCia(address _cia) external onlyOwner {
        require(_cia != address(0), "Mail: cia is the zero address");
        cia = IERC20(_cia);
    }

    function setWeth(address _weth) external onlyOwner {
        require(_weth != address(0), "Mail: weth is the zero address");
        weth = _weth;
    }

    function setUsdt(address _usdt) external onlyOwner {
        require(_usdt != address(0), "Mail: usdt is the zero address");
        usdt = _usdt;
    }

    function setFeeAddress(address _feeAddress) external onlyOwner {
        require(_feeAddress != address(0), "Mail: fee address is the zero address");
        feeAddress = _feeAddress;
    }

    function setFee(uint256 _fee) external onlyOwner {
        require(_fee > 0, "Mail: fee is 0");
        fee = _fee;
    }

    function removeFee() external onlyOwner {
        fee = 0;
    }

    function buy() external {
        address[] memory path = new address[](3);
        path[0] = address(cia);
        path[1] = weth;
        path[2] = usdt;

        uint256 amountNeeded = router.getAmountsIn(fee, path)[0];
        uint256 balance = cia.balanceOf(msg.sender);
        require(balance >= amountNeeded, "Mail: not enough balance");
        require(cia.allowance(msg.sender,address(this)) >= amountNeeded, "Mail: allowance too low");
        require(cia.transferFrom(msg.sender,feeAddress,amountNeeded), "Mail: transfer failed");

        balances[msg.sender]++;

        emit Buy(msg.sender, amountNeeded);
    }
}