// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;

    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }

    /**
     * Function modifier to require caller to be contract owner
     */
    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    /**
     * Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    /**
     * Authorize address. Owner only
     */
    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    /**
     * Remove address' authorization. Owner only
     */
    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }

    /**
     * Check if address is owner
     */
    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    /**
     * Return address' authorization status
     */
    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    /**
     * Transfer ownership to new address. Caller must be owner. Leaves old owner authorized
     */
    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }

    event OwnershipTransferred(address owner);
}


interface IERC20 {
	function transfer(address recipient, uint256 amount) external returns (bool);
	function balanceOf(address account) external view returns (uint256);
	function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

interface IRouter {
	function WETH() external pure returns (address);
	function swapExactETHForTokensSupportingFeeOnTransferTokens(uint amountOutMin, address[] calldata path, address to, uint deadline) external payable;
}

abstract contract Hibiki is IERC20 {
	address public feeReceiver;
}

/**
 * @dev Contract that manages Hibiki token flow and buybacks on Ethereum mainnet.
 */
contract HibikiFlowEth is Auth {

	address public hibiki;
	IRouter private router;
	uint8 public devFeeDivisor = 2;
	uint256 private sendGas = 34000;
	uint256 public ethTreshold = 0.1 ether;

	constructor(address h, address r) Auth(msg.sender) {
		hibiki = h;
		router = IRouter(r);
	}

	receive() external payable {
		deposit();
	}

	/**
	 * @dev Every time ether is sent to this contract, if it's above treshold it will be used.
	 */
	function deposit() public payable {
		if (address(this).balance > ethTreshold) {
			process();
		}
	}

	function process() public {
		if (devFeeDivisor > 0) {
			uint256 devWorksHard = address(this).balance / devFeeDivisor;
			_sendGas(owner, devWorksHard);
		}
		if (address(this).balance > 0) {
			_buyHibiki(address(this).balance);
			sendHibiki();
		}
	}

	/**
	 * @dev Manually get gas out of contract.
	 */
	function rescue() external {
		_sendGas(owner, address(this).balance);
	}

	function _sendGas(address receiver, uint256 val) internal returns (bool result) {
		(result,) = receiver.call{value: val, gas: sendGas}("");
	}

	/**
	 * @dev Buys the hibiki token with the specified ether amount.
	 */
	function _buyHibiki(uint256 amount) internal {
		address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = hibiki;
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amount}(
            0,
            path,
            address(this),
            block.timestamp
        );
	}

	/**
	 * @dev Sends accrued Hibiki to the current fee receiver, usually LP staking contract.
	 */
	function sendHibiki() public {
		Hibiki t = Hibiki(hibiki);
		uint256 amount = t.balanceOf(address(this));
		if (amount > 0) {
			t.transfer(t.feeReceiver(), amount);
		}
	}

	/**
	 * @dev Recovers ERC20 tokens sent to this contract.
	 */
	function recoverToken(address token) internal {
		IERC20 t = IERC20(token);
		t.transfer(token, t.balanceOf(address(this)));
	}

	function setSendGas(uint256 gas) external authorized {
		sendGas = gas;
	}

	function setRouter(address rout) external authorized {
		router = IRouter(rout);
	}

	function setHibiki(address h) external authorized {
		hibiki = h;
	}

	function setDevDivisor(uint8 divisor) external authorized {
		devFeeDivisor = divisor;
	}

	function setEthTreshold(uint256 treshold) external authorized {
		ethTreshold = treshold;
	}
}