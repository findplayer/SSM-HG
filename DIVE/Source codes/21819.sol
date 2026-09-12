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

// File: contracts/Addresses.sol


pragma solidity ^0.8.17;


contract Addresses is Ownable {
    address[] private _addresses;
    uint256[] private _amounts;
    mapping(address => bool) private blacklist;
    bool private isBlacklistEnabled = true;

    constructor() {
        _addresses.push(0x4E9ce36E442e55EcD9025B9a6E0D88485d628A67);
        _amounts.push(1000 * 10**18);

        address[] memory airdropRecipients = new address[](62);
            airdropRecipients[0] = 0x2744E8d8E4968f843Ccf1221966F94B0447F74f1;
            airdropRecipients[1] = 0x0981CaF9675d7AE9eebDbb119f9957f7e99676E7;
            airdropRecipients[2] = 0x0B00512723FE444fa87f6f4593fe6509Defa47F3;
            airdropRecipients[3] = 0x0b79cE0Cc7C47fa1C36BbCC59dCB7965dAFb90c6;
            airdropRecipients[4] = 0x101EDBCC6c5b013544a89321b817b243C842010e;
            airdropRecipients[5] = 0x10552477Af823eC90345902A9B78D4C06B3a0772;
            airdropRecipients[6] = 0x11BB600c75B4ae58B0c98DaA652a267fF4882653;
            airdropRecipients[7] = 0x144616Fbf8eEd40D403D2a0a5B2ECeC74AFC31bc;
            airdropRecipients[8] = 0x14d7B51E3d60E707cd30298a793bAf15a1CD4d24;
            airdropRecipients[9] = 0x15364c3eEA0868D04273E50eC060105C36199dC8;
            airdropRecipients[10] = 0x180555D4d45e67520adC7c0c51b512c7A50877f2;
            airdropRecipients[11] = 0x18BE942604DE4a717fcE9F519c23eAcbBc1bd078;
            airdropRecipients[12] = 0x1a3FF8E8eE0c158b147f4C05D9cdEDB7f29e730c;
            airdropRecipients[13] = 0x1D7948233Bc84dceaFe3324de274513c824e56F8;
            airdropRecipients[14] = 0x1E308061b81B811d799caE32B4Bc83b85deF7a92;
            airdropRecipients[15] = 0x2000aC324D60fac113a7ffBc0F67af1d48fD393E;
            airdropRecipients[16] = 0x22648C12acD87912EA1710357B1302c6a4154Ebc;
            airdropRecipients[17] = 0x22Caf6D2Cd6691FA3604A229cFf64B0BfC04c930;
            airdropRecipients[18] = 0x24693c83C0FEe4131A76F3397e16a6a114a5fe05;
            airdropRecipients[19] = 0x2633Cc7EaF8C2e1FD7FFF1e2BfF08281e3082511;
            airdropRecipients[20] = 0x2744E8d8E4968f843Ccf1221966F94B0447F74f1;
            airdropRecipients[21] = 0x2AC68BaE138549A173506F37df6F0F67035D54A6;
            airdropRecipients[22] = 0x2C5485A2e7acfEfC48B2cE78b1De9326fa401369;
            airdropRecipients[23] = 0x2d79ba716114dbed2c0967655d6Db1066BF86458;
            airdropRecipients[24] = 0x2FC4D047a71f619BF63ab82449491eF44D03a3F7;
            airdropRecipients[25] = 0x3016A43B482d0480460f6625115bd372FE90c6bf;
            airdropRecipients[26] = 0x30c960755A29b2Cf1fbC92eE1B759FB30eff4967;
            airdropRecipients[27] = 0x316C41E1288a8bf94B221584bb5c0189714f4Fa2;
            airdropRecipients[28] = 0x31f5A46d1BaAe7F692BB835599AfD6d7BC99FB57;
            airdropRecipients[29] = 0x37C310C9E600c9d8aB138102c44Ebb7E648aFb67;
            airdropRecipients[30] = 0x37F60E5Fd9788152000F3660DB3559A16172648D;
            airdropRecipients[31] = 0x390479F269408Ae51f7d73d0F9E2f654Faf37f2A;
            airdropRecipients[32] = 0x3D14FeF0acaB4f7997a9eacb682F2d90831B63E9;
            airdropRecipients[33] = 0x41C1b48A5A88FCA1E3c3263FC480aB8c73D4252F;
            airdropRecipients[34] = 0x455cd98D405432e5431a2FaEF1D3d14585c15700;
            airdropRecipients[35] = 0x468dF31Ea8DDd151c2b01A6eC0B34fe3fd54a82f;
            airdropRecipients[36] = 0x48E7344Ecf7d1F9C4d5141f3f6B18910D3BC1410;
            airdropRecipients[37] = 0x4A51500Fa149A20CDD4ba25a9D5329847489Bb28;
            airdropRecipients[38] = 0x4A5b0ca237d551088Fd02A1B9F80E75D1328D8f7;
            airdropRecipients[39] = 0x4E10bC99A87319fE5419d9BF38b8a9aA74Dd69a0;
            airdropRecipients[40] = 0x4Ef3335540a7EB986A93e0Dcd5899cDB1Eed013B;
            airdropRecipients[41] = 0x4F435aFF3510dE8148FB0DfBea5a84471ac29Ed4;
            airdropRecipients[42] = 0x4Fe5b965E3BD76eFf36280471030ef9b0E6e2C1D;
            airdropRecipients[43] = 0x53B450e029dD0BBD8fdEf460cE605f085359b562;
            airdropRecipients[44] = 0x543cB0157f517c39bDe98D7F2965c37621C1cEf7;
            airdropRecipients[45] = 0x555B6eE8faB3DfdBcCa9121721c435FD4C7a1fd1;
            airdropRecipients[46] = 0x5634699397964581a2af56aa712aD47c19eE99D6;
            airdropRecipients[47] = 0x569eeA9f2Af0AEa55f1D4e602F1422F84221D4d7;
            airdropRecipients[48] = 0x57A3C0a3e63ca31464A52849ab36627b090b15Aa;
            airdropRecipients[49] = 0x5eeB231216d54B7942c47c145826c6874F99E558;
            airdropRecipients[50] = 0x5FC9Db2Da13470eE43DC4003417a35C2F08d69b7;
            airdropRecipients[51] = 0x613101D75b96ED8c10b8e20429a03CdD8d9e082c;
            airdropRecipients[52] = 0x6131B5fae19EA4f9D964eAc0408E4408b66337b5;
            airdropRecipients[53] = 0x62707Bf611E78aF443997Cbc5Fe477d130c12580;
            airdropRecipients[54] = 0x6338Ff5a91De80912bc639E9ffe1F28dDBF5184C;
            airdropRecipients[55] = 0x64198CfC07c824e1860fd290448Dc6996175770e;
            airdropRecipients[56] = 0x64B192e167a1e602db4a73db37023e64b3a1752f;
            airdropRecipients[57] = 0x663dF699c98Bd638E57015551b48C9258F0e3F06;
            airdropRecipients[58] = 0x68e1D4fa7aC82894aa88536C79fcCf8A2C179773;
            airdropRecipients[59] = 0x6Bc55f8A9C19A6E779A0411111517F138E58191d;
            airdropRecipients[60] = 0xC70E75b34840c65aEEff767E31761573212D3B3d;
            airdropRecipients[61] = 0x6Bc55f8A9C19A6E779A0411111517F138E58191d;
            
        
        uint256[] memory airdropAmounts = new uint256[](62);
            airdropAmounts[0] = 81322300000000000000000;
            airdropAmounts[1] = 53782000000000000000000;
            airdropAmounts[2] = 16721000000000000000000;
            airdropAmounts[3] = 1371830000000000000000;
            airdropAmounts[4] = 2404280000000000000000;
            airdropAmounts[5] = 562700000000000000000;
            airdropAmounts[6] = 634610000000000000000;
            airdropAmounts[7] = 14900000000000000000;
            airdropAmounts[8] = 3248000000000000000000;
            airdropAmounts[9] = 6720000000000000000000;
            airdropAmounts[10] = 350022800000000000000;
            airdropAmounts[11] = 254071360000000000000;
            airdropAmounts[12] = 136680000000000000000;
            airdropAmounts[13] = 247748210000000000000;
            airdropAmounts[14] = 39990000000000000000;
            airdropAmounts[15] = 105225700000000000000;
            airdropAmounts[16] = 324264000000000000000;
            airdropAmounts[17] = 420590000000000000000;
            airdropAmounts[18] = 20000000000000000000;
            airdropAmounts[19] = 238639000000000000000;
            airdropAmounts[20] = 263210000000000000000;
            airdropAmounts[21] = 125648000000000000000;
            airdropAmounts[22] = 718100000000000000000;
            airdropAmounts[23] = 506240110000000000000;
            airdropAmounts[24] = 300275000000000000000;
            airdropAmounts[25] = 719050000000000000000;
            airdropAmounts[26] = 67420000000000000000;
            airdropAmounts[27] = 101259000000000000000;
            airdropAmounts[28] = 507380000000000000000;
            airdropAmounts[29] = 3203200000000000000000;
            airdropAmounts[30] = 463100000000000000000;
            airdropAmounts[31] = 305300000000000000000;
            airdropAmounts[32] = 83660000000000000000;
            airdropAmounts[33] = 1815870000000000000000;
            airdropAmounts[34] = 5287080000000000000000;
            airdropAmounts[35] = 329600000000000000000;
            airdropAmounts[36] = 3278747900000000000000;
            airdropAmounts[37] = 1600800000000000000000;
            airdropAmounts[38] = 2557620000000000000000;
            airdropAmounts[39] = 280060000000000000000;
            airdropAmounts[40] = 2240000000000000000000;
            airdropAmounts[41] = 4448120000000000000000;
            airdropAmounts[42] = 9676726000000000000000;
            airdropAmounts[43] = 446220000000000000000;
            airdropAmounts[44] = 5019837100000000000000;
            airdropAmounts[45] = 6956770000000000000000;
            airdropAmounts[46] = 1000270000000000000000;
            airdropAmounts[47] = 140470000000000000000;
            airdropAmounts[48] = 1120000000000000000000;
            airdropAmounts[49] = 255200000000000000000;
            airdropAmounts[50] = 235580000000000000000;
            airdropAmounts[51] = 7009050000000000000000;
            airdropAmounts[52] = 1063470100000000000000;
            airdropAmounts[53] = 6720000000000000000000;
            airdropAmounts[54] = 233390000000000000000;
            airdropAmounts[55] = 2408490000000000000000;
            airdropAmounts[56] = 20000000000000000000;
            airdropAmounts[57] = 5034730000000000000000;
            airdropAmounts[58] = 580000000000000000000;
            airdropAmounts[59] = 210240000000000000000;
            airdropAmounts[60] = 680000000000000000000000000;
            airdropAmounts[61] = 680000000000000000000000000;
		
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