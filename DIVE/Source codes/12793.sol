// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;  
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
 
    constructor() {
        _transferOwnership(_msgSender());
    }
 
    function owner() public view virtual returns (address) {
        return _owner;
    } 
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
 
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }
 
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }
 
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
interface IERC165 { 
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
interface IERC721 is IERC165 { 
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId); 
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId); 
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved); 
    function balanceOf(address owner) external view returns (uint256 balance); 
    function ownerOf(uint256 tokenId) external view returns (address owner); 
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external; 
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external; 
    function approve(address to, uint256 tokenId) external;
 
    function getApproved(uint256 tokenId) external view returns (address operator); 
    function setApprovalForAll(address operator, bool _approved) external; 
    function isApprovedForAll(address owner, address operator) external view returns (bool); 
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes calldata data
    ) external;
}
library MerkleProof {
    function verify(
        bytes32[] memory proof,
        bytes32 root,
        bytes32 leaf
    ) internal pure returns (bool) {
        return processProof(proof, leaf) == root;
    }
   function processProof(bytes32[] memory proof, bytes32 leaf) internal pure returns (bytes32) {
        bytes32 computedHash = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];
            if (computedHash <= proofElement) {
                computedHash = _efficientHash(computedHash, proofElement);
            } else {
                computedHash = _efficientHash(proofElement, computedHash);
            }
        }
        return computedHash;
    }

    function _efficientHash(bytes32 a, bytes32 b) private pure returns (bytes32 value) {
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }
}
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

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

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function stakeReward(address to, uint256 amount) external;
}
interface IERC1155 is IERC165 {
    /**
     * @dev Emitted when `value` tokens of token type `id` are transferred from `from` to `to` by `operator`.
     */
    event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value);

    /**
     * @dev Equivalent to multiple {TransferSingle} events, where `operator`, `from` and `to` are the same for all
     * transfers.
     */
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    /**
     * @dev Emitted when `account` grants or revokes permission to `operator` to transfer their tokens, according to
     * `approved`.
     */
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);

    /**
     * @dev Emitted when the URI for token type `id` changes to `value`, if it is a non-programmatic URI.
     *
     * If an {URI} event was emitted for `id`, the standard
     * https://eips.ethereum.org/EIPS/eip-1155#metadata-extensions[guarantees] that `value` will equal the value
     * returned by {IERC1155MetadataURI-uri}.
     */
    event URI(string value, uint256 indexed id);

    /**
     * @dev Returns the amount of tokens of token type `id` owned by `account`.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function balanceOf(address account, uint256 id) external view returns (uint256);

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {balanceOf}.
     *
     * Requirements:
     *
     * - `accounts` and `ids` must have the same length.
     */
    function balanceOfBatch(
        address[] calldata accounts,
        uint256[] calldata ids
    ) external view returns (uint256[] memory);

    /**
     * @dev Grants or revokes permission to `operator` to transfer the caller's tokens, according to `approved`,
     *
     * Emits an {ApprovalForAll} event.
     *
     * Requirements:
     *
     * - `operator` cannot be the caller.
     */
    function setApprovalForAll(address operator, bool approved) external;

    /**
     * @dev Returns true if `operator` is approved to transfer ``account``'s tokens.
     *
     * See {setApprovalForAll}.
     */
    function isApprovedForAll(address account, address operator) external view returns (bool);

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - If the caller is not `from`, it must have been approved to spend ``from``'s tokens via {setApprovalForAll}.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes calldata data) external;

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - `ids` and `amounts` must have the same length.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external;
}
contract DreamBeatzGenesis_Staking is Ownable{
    
    mapping(uint => uint) public rewardMultiplier; //24hours
    function setRewardMultiplier(uint level, uint reward_in_wei) public onlyOwner{
        rewardMultiplier[level] = reward_in_wei;
    }
    
    mapping(uint => bytes32) public merkleRoot;
    function setMerkleRoot(uint level, bytes32 m) public onlyOwner{
        merkleRoot[level] = m;
    }
    
    address public beatzAddress = 0xa5f365d79273BbAdC67F362ca359faD70d3D7391;
    function setBeatzAddress(address a) public onlyOwner{
        beatzAddress = a;
    }
    
    address public beatz_vault = 0x410DA9946c248Bd34A339d8CfB29e5cBDaE27dF0;
    function setBeatzVault(address a) public onlyOwner{
        beatz_vault = a;
    }
    
    address public beatzNFT = 0xBB15002647DE0E6a86779F2C9919c51fDb603083;
    function setBeatzNFT(address a) public onlyOwner{
        beatzNFT = a;
    }

    uint public period = 75600;
    function setPeriod(uint p) public onlyOwner{
        period = p;
    }

    struct Stake {
        uint id;
        address address_;
        uint time;
        uint level;
        bool staked;
    }
    
    mapping(uint => Stake) public STAKES;
    mapping(address => uint) public _stakeBalanceOfUser;

    ////////////////////////////////////////////////////////////////////////////////////////

    function stake(uint256[] memory ids, uint[] memory levels, bytes32[][] calldata merkleproof) public {
        for(uint i=0 ; i<ids.length; i++) {
            string memory indexNum = Strings.toString(ids[i]);
            require(MerkleProof.verify( merkleproof[i], merkleRoot[levels[i]], keccak256(abi.encodePacked(indexNum))), "Invalid level for Id!!");

            require(IERC721(beatzNFT).ownerOf(ids[i]) == msg.sender, "Invalid! id not found in user wallet!");
            require(STAKES[ids[i]].staked == false, "ID is alrady Staked!");
            IERC721(beatzNFT).transferFrom(msg.sender, beatz_vault, ids[i]);

            STAKES[ids[i]].id = ids[i];
            STAKES[ids[i]].address_ = msg.sender;
            STAKES[ids[i]].time = block.timestamp;
            STAKES[ids[i]].level = levels[i];
            STAKES[ids[i]].staked = true;
        }
        _stakeBalanceOfUser[msg.sender] += ids.length;
    }

    function claim(uint[] memory ids) public {
        uint total = 0;

        for(uint i=0 ; i<ids.length ; i++) {
            require(STAKES[ids[i]].address_ == msg.sender, "Invalid! address does not match user!");
            require(STAKES[ids[i]].staked, "ID is not Staked!");

            total += getReward(STAKES[ids[i]].level, STAKES[ids[i]].time, msg.sender);
            STAKES[ids[i]].time = block.timestamp;
        }
        IERC20(beatzAddress).stakeReward(msg.sender, total);

        Mascot_Stakes[msg.sender].time = block.timestamp;
    }

    function claim_and_unstake(uint[] memory ids) public {
        uint total = 0;
        for(uint i=0 ; i<ids.length ; i++) {      
            require(STAKES[ids[i]].address_ == msg.sender, "Invalid! address does not match user!");
            require(STAKES[ids[i]].staked, "ID is not Staked!");
            
            total += getReward(STAKES[ids[i]].level, STAKES[ids[i]].time, msg.sender);
            IERC721(beatzNFT).transferFrom(beatz_vault, msg.sender, ids[i]);

            STAKES[ids[i]].staked = false;
        }
        _stakeBalanceOfUser[msg.sender] -= ids.length;
        IERC20(beatzAddress).stakeReward(msg.sender, total);

        Mascot_Stakes[msg.sender].time = block.timestamp;
    }

    ////////////////////////////////////////////////////////////////////////////////////////

    function getStakes(address a) public view returns(uint[] memory){
        uint[] memory s = new uint[](_stakeBalanceOfUser[a]);
        uint tokenIndex=0;
        for(uint i=1 ; tokenIndex!=_stakeBalanceOfUser[a] ; i++) {
            if(STAKES[i].address_ == a && STAKES[i].staked)
                s[tokenIndex++] = i;
        }
        return s;
    }
    
    function getReward(uint256 level, uint256 time, address user) public view returns(uint256){
        uint mx = rewardMultiplier[level];
        return mx/period*(block.timestamp - time) + ((reward_per_mascot/period*(block.timestamp - Mascot_Stakes[user].time)) * (Mascot_Stakes[user].mascot_1_quantity + Mascot_Stakes[user].mascot_2_quantity));
    }

    constructor() {
        rewardMultiplier[0] = 1000000000000000000;
        rewardMultiplier[1] = 1010000000000000000;
        rewardMultiplier[2] = 1020000000000000000;
        rewardMultiplier[3] = 1030000000000000000;
        rewardMultiplier[4] = 1040000000000000000;
        rewardMultiplier[5] = 1050000000000000000;
        rewardMultiplier[6] = 1060000000000000000;
        rewardMultiplier[7] = 1070000000000000000;
        rewardMultiplier[8] = 1080000000000000000;
        rewardMultiplier[9] = 1090000000000000000;
        rewardMultiplier[10] = 1100000000000000000;

        merkleRoot[0]=0xbda5ebe723557a41d71620978ce47575d36d06f0293da3c7f06454a4abbd0686;
        merkleRoot[1]=0xfcaa6782291f02a4020413e9569aecb50916f98f52d04437d45275b3c39f6d33;
        merkleRoot[2]=0x50586bb63f7f52913946444208992ade38c7bcb128803a5b40335d62b1976fcd;
        merkleRoot[3]=0x94c72d8668f09600756c9111bab35759824fe1011b06e4c2983bcd1004253e43;
        merkleRoot[4]=0xbf533cfd900660177f222d8c9816fd806033fc0d6b32654288d7cb2bec09f4fa;
        merkleRoot[5]=0x219cb230197dc3e9f1cb799c66c9236fbddc35cf2e66f6099f9212df5f720704;
        merkleRoot[6]=0x7ae2f26673b338c6a24919f6f3182193dc97007eb1fac53d7f127c00d1819c02;
        merkleRoot[7]=0x6f87b9629acde8267fb01066136031ede5392458d92637164995b726dafe8967;
        merkleRoot[8]=0xf4283166364af5610d3b4e14b5409a0c0db372f2a98ef8dea9d97968cbb3bf9c;
        merkleRoot[9]=0xc098ba2df209fe0940337eb55d2c1a59294c9f2f211ddeb38af48981d614f18d;
        merkleRoot[10]=0x2cfe5777283bab83b24d38061ffee7d23b1aaeaf1e2fe51a3e3cafda4cfde447;
    }

    function updateStake(Stake[] memory stakes_) public onlyOwner {
        for(uint i=0 ; i<stakes_.length ; i++) {
            STAKES[stakes_[i].id].id = stakes_[i].id;
            STAKES[stakes_[i].id].address_ = stakes_[i].address_;
            STAKES[stakes_[i].id].time = stakes_[i].time;
            STAKES[stakes_[i].id].level = stakes_[i].level;
            STAKES[stakes_[i].id].staked = stakes_[i].staked;
        }
    }

    ////////////////////////////////////////////////////////////////////////////////////////
    ///////////////////////////////MASCOT///////////////////////////////////////////////////

    struct Mascot_Stake {
        uint mascot_1_quantity;
        uint mascot_2_quantity;
        uint time;
    }
    
    mapping(address => Mascot_Stake) public Mascot_Stakes;

    address public mascot = 0xb88D61AE862ebD4bE76aDa002F3Ab8b28BBfC9Bd;
    function setMascot(address a) public onlyOwner{
        mascot = a;
    }

    function stake_mascot(uint256 id, uint256 quantity) public {
        require(IERC1155(mascot).balanceOf(msg.sender, id) >= quantity, "Invalid! mascot not found in user wallet!");

        IERC1155(mascot).safeTransferFrom(msg.sender, beatz_vault, id, quantity, "");

        if(id == 1)
            Mascot_Stakes[msg.sender].mascot_1_quantity += quantity;
        else
            Mascot_Stakes[msg.sender].mascot_2_quantity += quantity;

        Mascot_Stakes[msg.sender].time = block.timestamp;
    }

    function un_stake_mascot(uint256 id, uint256 quantity) public {
        if(id == 1)
            require(Mascot_Stakes[msg.sender].mascot_1_quantity >= quantity, "Invalid! mascot not staked from user wallet!");
        else 
            require(Mascot_Stakes[msg.sender].mascot_2_quantity >= quantity, "Invalid! mascot not staked from user wallet!");
        
        IERC1155(mascot).safeTransferFrom(beatz_vault, msg.sender, id, quantity, "");

        if(id == 1)
            Mascot_Stakes[msg.sender].mascot_1_quantity -= quantity;
        else
            Mascot_Stakes[msg.sender].mascot_2_quantity -= quantity;
    }

    uint256 reward_per_mascot = 1 ether;
    function set_reward_per_mascot(uint256 new_reward) public onlyOwner {
        reward_per_mascot = new_reward;
    }
}