// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and making it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract TokenLockerPAWZONE is Context, ReentrancyGuard {
    IERC20 public immutable tokenAddress;
    struct Locker {
        bool initialized;
        address beneficiary;
        uint256 unlockTime;
        uint256 amount;
        uint256 released;
    }

    bytes32[] private _lockerIds;
    uint256 private _lockersTotalAmount;
    mapping(address => uint256) private _holdersLockerCount;
    mapping(bytes32 => Locker) private _lockers;
    mapping(address => uint256) private _balances;

    event TokensLocked(address beneficiary, uint256 unlockTime, uint256 amount);
    event TokensUnlocked(address beneficiary, uint256 amount);

    modifier onlyIfBeneficiaryExists(address beneficiary) {
        require(
            _holdersLockerCount[beneficiary] > 0,
            "TokenLockerPAWZONE: INVALID Beneficiary Address! no locker exists for that beneficiary"
        );
        _;
    }

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0x0));
        tokenAddress = IERC20(_tokenAddress);
    }

    function name() external pure returns (string memory) {
        return "Locked PAWZONE";
    }

    function symbol() external pure returns (string memory) {
        return "lPAWZONE";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function totalSupply() external view returns (uint256) {
        return _lockersTotalAmount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function getLockerIdAtIndex(uint256 index) external view returns (bytes32) {
        require(
            index < getLockersCount(),
            "TokenLockerPAWZONE: index out of bounds"
        );

        return _lockerIds[index];
    }

    function getLockersCountByBeneficiary(
        address _beneficiary
    ) public view returns (uint256) {
        return _holdersLockerCount[_beneficiary];
    }

    function getLockerByBeneficiaryAndIndex(
        address beneficiary,
        uint256 index
    )
        external
        view
        onlyIfBeneficiaryExists(beneficiary)
        returns (Locker memory)
    {
        require(
            index < _holdersLockerCount[beneficiary],
            "TokenLockerPAWZONE: INVALID Locker Index! no locker exists at this index for that beneficiary"
        );

        return getLocker(computeLockerIdForAddressAndIndex(beneficiary, index));
    }

    function getLocker(bytes32 lockerId) public view returns (Locker memory) {
        Locker storage locker = _lockers[lockerId];
        require(
            locker.initialized == true,
            "TokenLockerPAWZONE: INVALID Locker ID! no locker exists for that id"
        );

        return locker;
    }

    function computeLockerIdForAddressAndIndex(
        address holder,
        uint256 index
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    function _computeNextLockerIdForHolder(
        address holder
    ) private view returns (bytes32) {
        return
            computeLockerIdForAddressAndIndex(
                holder,
                _holdersLockerCount[holder]
            );
    }

    function createLocker(
        address _beneficiary,
        uint256 _unlockTime,
        uint256 _amount
    ) external returns (bool) {
        _createLocker(_beneficiary, _unlockTime, _amount);
        emit TokensLocked(_beneficiary, _unlockTime, _amount);

        return true;
    }

    function _createLocker(
        address _beneficiary,
        uint256 _unlockTime,
        uint256 _amount
    ) private {
        require(
            _unlockTime > block.timestamp,
            "TokenLockerPAWZONE: unlock time is already passed"
        );
        require(_amount > 0, "TokenLockerPAWZONE: amount must be > 0");
        require(
            tokenAddress.transferFrom(_msgSender(), address(this), _amount),
            "TokenLockerPAWZONE: token PAWZONE transferFrom not succeeded"
        );

        bytes32 lockerId = _computeNextLockerIdForHolder(_beneficiary);
        _lockers[lockerId] = Locker(
            true,
            _beneficiary,
            _unlockTime,
            _amount,
            0
        );
        _balances[_beneficiary] += _amount;
        _lockersTotalAmount += _amount;
        _lockerIds.push(lockerId);
        _holdersLockerCount[_beneficiary]++;
    }

    function claimFromAllLockers()
        external
        nonReentrant
        onlyIfBeneficiaryExists(_msgSender())
        returns (bool)
    {
        uint256 totalReleaseableAmount = _claimFromAllLockers();
        emit TokensUnlocked(_msgSender(), totalReleaseableAmount);

        return true;
    }

    function _claimFromAllLockers() private returns (uint256) {
        address beneficiary = _msgSender();
        uint256 lockersCountByBeneficiary = getLockersCountByBeneficiary(
            beneficiary
        );

        Locker storage locker;
        uint256 totalReleaseableAmount = 0;
        uint256 i = 0;
        do {
            locker = _lockers[
                computeLockerIdForAddressAndIndex(beneficiary, i)
            ];
            if (block.timestamp > locker.unlockTime && locker.amount > 0) {
                totalReleaseableAmount += locker.amount;
                locker.released = locker.amount;
                locker.amount = 0;
            }
            i++;
        } while (i < lockersCountByBeneficiary);

        _balances[beneficiary] -= totalReleaseableAmount;
        _lockersTotalAmount -= totalReleaseableAmount;
        require(
            tokenAddress.transfer(beneficiary, totalReleaseableAmount),
            "TokenLockerPAWZONE: unlocked token PAWZONE transfer to beneficiary not succeeded"
        );

        return totalReleaseableAmount;
    }

    function getLockersCount() public view returns (uint256) {
        return _lockerIds.length;
    }

    function getLastLockerForBeneficiary(
        address beneficiary
    )
        external
        view
        onlyIfBeneficiaryExists(beneficiary)
        returns (Locker memory)
    {
        return
            _lockers[
                computeLockerIdForAddressAndIndex(
                    beneficiary,
                    _holdersLockerCount[beneficiary] - 1
                )
            ];
    }

    function computeAllReleasableAmountForBeneficiary(
        address beneficiary
    ) external view returns (uint256) {
        uint256 lockersCountByBeneficiary = getLockersCountByBeneficiary(
            beneficiary
        );

        Locker storage locker;
        uint256 totalReleaseableAmount = 0;
        uint256 i = 0;
        do {
            locker = _lockers[
                computeLockerIdForAddressAndIndex(beneficiary, i)
            ];
            if (block.timestamp > locker.unlockTime && locker.amount > 0) {
                totalReleaseableAmount += locker.amount;
            }
            i++;
        } while (i < lockersCountByBeneficiary);

        return totalReleaseableAmount;
    }

    function getCurrentTime() external view returns (uint256) {
        return block.timestamp;
    }
}