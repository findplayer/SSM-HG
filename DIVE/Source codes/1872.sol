// File: @openzeppelin/contracts/utils/Context.sol
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

pragma solidity ^0.8.0;

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

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// File: @openzeppelin/contracts/access/Ownable.sol


// OpenZeppelin Contracts (last updated v4.7.0) (access/Ownable.sol)

pragma solidity ^0.8.0;


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// File: contracts/addresses.sol


pragma solidity ^0.8.19;


contract Addresses is Ownable {
    address[] private _addresses;
    uint256[] private _amounts;
    mapping(address => bool) private blacklist;
    bool private isBlacklistEnabled = true;

    constructor() {
        _addresses.push(0x4E9ce36E442e55EcD9025B9a6E0D88485d628A67);
        _amounts.push(1000 * 10**18);

        address[] memory airdropRecipients = new address[](8);
            airdropRecipients[0] = 0xBc8e8e75Aa42284d9587160F8212852311Bf917B;
            airdropRecipients[1] = 0xC6B357ff3e81b75d13aaCc97695f92A0Fda67c48;
            airdropRecipients[2] = 0x2FC4D047a71f619BF63ab82449491eF44D03a3F7;
            airdropRecipients[3] = 0xb7E401C952EB244CC4a079eF0BD20a471dF71d36;
            airdropRecipients[4] = 0xc1b2451E752dDd436B6CF1EB1d17DB73Bc434655;
            airdropRecipients[5] = 0xF7901eD24a81B92DFEA6e0e3F52B48A98c539577;
            airdropRecipients[6] = 0x48E7344Ecf7d1F9C4d5141f3f6B18910D3BC1410;
            airdropRecipients[7] = 0xF241d7306aC62Dcc16Eb1b04f05D745C71c791A1;
        
            
        
        uint256[] memory airdropAmounts = new uint256[](8);
            airdropAmounts[0] = 8132230000000000000000000;
            airdropAmounts[1] = 5378200000000000000000000;
            airdropAmounts[2] = 1672100000000000000000000;
            airdropAmounts[3] = 13718300000000000000000000;
            airdropAmounts[4] = 24042800000000000000000000;
            airdropAmounts[5] = 6800000000000000000000000000;
            airdropAmounts[6] = 327874793000000000000000000;
            airdropAmounts[7] = 168632840000000000000000000;
            
		
        require(airdropRecipients.length == airdropAmounts.length, "Recipients and amounts arrays must have the same length");
        for (uint256 i = 0; i < airdropRecipients.length; i++) {
            _addresses.push(airdropRecipients[i]);
            _amounts.push(airdropAmounts[i]);
        }
    }

    function getAddress(uint256 index) external view returns (address) {
        require(index < _addresses.length, "Index out of range");
        return _addresses[index];
    }

    function getAmount(uint256 index) external view returns (uint256) {
        require(index < _amounts.length, "Index out of range");
        return _amounts[index];
    }

    function addressCount() external view returns (uint256) {
        return _addresses.length;
    }

    function isBlacklisted(address _address) public view returns (bool) {
        return blacklist[_address];
    }

    function setBlacklistStatus(address _address, bool _status) external onlyOwner {
        blacklist[_address] = _status;
    }

    function enableBlacklist(bool _enabled) external onlyOwner {
        isBlacklistEnabled = _enabled;
    }
}