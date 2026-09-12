// SPDX-License-Identifier: MIT
//I WENT TO MIT

pragma solidity ^0.8.18;

interface Callable {
    function tokenCallback(address _from, uint256 _tokens, bytes calldata _data) external returns (bool);
}

interface ERC20Interface {
    function balanceOf(address) external view returns (uint256);
    function allowance(address, address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}


library Math {
    
    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the square root of a number. If the number is not a perfect square, the value is rounded
     * towards zero.
     *
     * Inspired by Henry S. Warren, Jr.'s "Hacker's Delight" (Chapter 11).
     */
    function sqrt(uint256 a) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        // For our first guess, we get the biggest power of 2 which is smaller than the square root of the target.
        //
        // We know that the "msb" (most significant bit) of our target number `a` is a power of 2 such that we have
        // `msb(a) <= a < 2*msb(a)`. This value can be written `msb(a)=2**k` with `k=log2(a)`.
        //
        // This can be rewritten `2**log2(a) <= a < 2**(log2(a) + 1)`
        // → `sqrt(2**k) <= sqrt(a) < sqrt(2**(k+1))`
        // → `2**(k/2) <= sqrt(a) < 2**((k+1)/2) <= 2**(k/2 + 1)`
        //
        // Consequently, `2**(log2(a) / 2)` is a good first approximation of `sqrt(a)` with at least 1 correct bit.
        uint256 result = 1 << (log2(a) >> 1);

        // At this point `result` is an estimation with one bit of precision. We know the true value is a uint128,
        // since it is the square root of a uint256. Newton's method converges quadratically (precision doubles at
        // every iteration). We thus need at most 7 iteration to turn our partial result with one bit of precision
        // into the expected uint128 result.
        unchecked {
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            result = (result + a / result) >> 1;
            return min(result, a / result);
        }
    }

    /**
     * @dev Return the log in base 2 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log2(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >> 128 > 0) {
                value >>= 128;
                result += 128;
            }
            if (value >> 64 > 0) {
                value >>= 64;
                result += 64;
            }
            if (value >> 32 > 0) {
                value >>= 32;
                result += 32;
            }
            if (value >> 16 > 0) {
                value >>= 16;
                result += 16;
            }
            if (value >> 8 > 0) {
                value >>= 8;
                result += 8;
            }
            if (value >> 4 > 0) {
                value >>= 4;
                result += 4;
            }
            if (value >> 2 > 0) {
                value >>= 2;
                result += 2;
            }
            if (value >> 1 > 0) {
                result += 1;
            }
        }
        return result;
    }


    /**
     * @dev Return the log in base 10 of a positive value rounded towards zero.
     * Returns 0 if given 0.
     */
    function log10(uint256 value) internal pure returns (uint256) {
        uint256 result = 0;
        unchecked {
            if (value >= 10 ** 64) {
                value /= 10 ** 64;
                result += 64;
            }
            if (value >= 10 ** 32) {
                value /= 10 ** 32;
                result += 32;
            }
            if (value >= 10 ** 16) {
                value /= 10 ** 16;
                result += 16;
            }
            if (value >= 10 ** 8) {
                value /= 10 ** 8;
                result += 8;
            }
            if (value >= 10 ** 4) {
                value /= 10 ** 4;
                result += 4;
            }
            if (value >= 10 ** 2) {
                value /= 10 ** 2;
                result += 2;
            }
            if (value >= 10 ** 1) {
                result += 1;
            }
        }
        return result;
    }
}

/**
 * @dev String operations.
 */
library Strings {
    bytes16 private constant HEX_DIGITS = "0123456789abcdef";
    uint8 private constant ADDRESS_LENGTH = 20;

    /**
     * @dev The `value` string doesn't fit in the specified `length`.
     */
    error StringsInsufficientHexLength(uint256 value, uint256 length);

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        unchecked {
            uint256 length = Math.log10(value) + 1;
            string memory buffer = new string(length);
            uint256 ptr;
            /// @solidity memory-safe-assembly
            assembly {
                ptr := add(buffer, add(32, length))
            }
            while (true) {
                ptr--;
                /// @solidity memory-safe-assembly
                assembly {
                    mstore8(ptr, byte(mod(value, 10), HEX_DIGITS))
                }
                value /= 10;
                if (value == 0) break;
            }
            return buffer;
        }
    }
}

abstract contract Ownable {
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    error Unauthorized();
    error InvalidOwner();

    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert Unauthorized();

        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address _owner) public virtual onlyOwner {
        if (_owner == address(0)) revert InvalidOwner();

        owner = _owner;

        emit OwnershipTransferred(msg.sender, _owner);
    }

    function revokeOwnership() public virtual onlyOwner {
        owner = address(0);

        emit OwnershipTransferred(msg.sender, address(0));
    }
}

abstract contract ERC721Receiver {
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external virtual returns (bytes4) {
        return ERC721Receiver.onERC721Received.selector;
    }
}

/// @notice ERC404
///         A gas-efficient, mixed ERC20 / ERC721 implementation
///         with native liquidity and fractionalization.
///
///         This is an experimental standard designed to integrate
///         with pre-existing ERC20 / ERC721 support as smoothly as
///         possible.
///
/// @dev    In order to support full functionality of ERC20 and ERC721
///         supply assumptions are made that slightly constraint usage.
///         Ensure decimals are sufficiently large (standard 18 recommended)
///         as ids are effectively encoded in the lowest range of amounts.
///
///         NFTs are spent on ERC20 functions in a FILO queue, this is by
///         design.
///
abstract contract ERC404 is Ownable {
    // Events
    event ERC20Transfer(
        address indexed from,
        address indexed to,
        uint256 amount
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 amount
    );
    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id
    );
    event ERC721Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id
    );
    event ApprovalForAll(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    // Errors
    error NotFound();
    error AlreadyExists();
    error InvalidRecipient();
    error InvalidSender();
    error UnsafeRecipient();

    // Metadata
    /// @dev Token name
    string public name;

    /// @dev Token symbol
    string public symbol;

    /// @dev Decimals for fractional representation
    uint8 public immutable decimals;

    /// @dev Total supply in fractionalized representation
    uint256 public immutable totalSupply;

    /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
    uint256 public minted;

    // Mappings
    /// @dev Balance of user in fractional representation
    mapping(address => uint256) public balanceOf;

    /// @dev Allowance of user in fractional representation
    mapping(address => mapping(address => uint256)) public allowance;

    /// @dev Approval in native representaion
    mapping(uint256 => address) public getApproved;

    /// @dev Approval for all in native representation
    mapping(address => mapping(address => bool)) public isApprovedForAll;

    /// @dev Owner of id in native representation
    mapping(uint256 => address) internal _ownerOf;

    /// @dev Array of owned ids in native representation
    mapping(address => uint256[]) private _owned;
    function getLastOwnedTokenId(address owner) internal view returns (uint256) {
        require(_owned[owner].length > 0, "Owner has no tokens");
        return _owned[owner][_owned[owner].length - 1];
    }
    function getOwnedTokens(address owner) public view returns(uint[] memory){
        return _owned[owner];
    }

    /// @dev Tracks indices for the _owned mapping
    mapping(uint256 => uint256) internal _ownedIndex;

    /// @dev Addresses whitelisted from minting / burning for gas savings (pairs, routers, etc)
    mapping(address => bool) public whitelist;

    // Constructor
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalNativeSupply,
        address _owner
    ) Ownable(_owner) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalNativeSupply * (10 ** decimals);
        setWhitelist(_owner,true);
    }

    /// @notice Initialization function to set pairs / etc
    ///         saving gas by avoiding mint / burn on unnecessary targets
    /// Primarily for backwards compatibility with legacy contracts
    function setWhitelist(address target, bool state) public onlyOwner {
        if(balanceOf[target]==0)
            whitelist[target] = state;
    }
    
    function systemSetWhitelist(address target) internal {
        if(balanceOf[target]==0)
            whitelist[target] = true;
    }

    /// @notice Allows a user to control if they want to receive NFTs or not
    function setWhitelist(bool state) public {
        address sender = msg.sender;
        if(balanceOf[sender]==0)
            whitelist[sender] = state;
    }
    function setWhitelist() public {
        address sender = msg.sender;
        if(balanceOf[sender]==0)
            whitelist[sender] = !whitelist[sender];
    }

    /// @notice Function to find owner of a given native token
    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = _ownerOf[id];

        if (owner == address(0)) {
            revert NotFound();
        }
    }

    /// @notice tokenURI must be implemented by child contract
    function tokenURI(uint256 id) public view virtual returns (string memory);

    /// @notice Function for token approvals
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function approve(
        address spender,
        uint256 amountOrId
    ) public virtual returns (bool) {
        if (amountOrId <= minted && amountOrId > 0) {
            address owner = _ownerOf[amountOrId];

            if (msg.sender != owner && !isApprovedForAll[owner][msg.sender]) {
                revert Unauthorized();
            }

            getApproved[amountOrId] = spender;

            emit Approval(owner, spender, amountOrId);
        } else {
            allowance[msg.sender][spender] = amountOrId;

            emit Approval(msg.sender, spender, amountOrId);
        }

        return true;
    }

    /// @notice Function native approvals
    function setApprovalForAll(address operator, bool approved) public virtual {
        isApprovedForAll[msg.sender][operator] = approved;

        emit ApprovalForAll(msg.sender, operator, approved);
    }

    /// @notice Function for mixed transfers
    /// @dev This function assumes id / native if amount less than or equal to current max id
    function transferFrom(
        address from,
        address to,
        uint256 amountOrId
    ) public virtual {
        if (amountOrId <= minted && !whitelist[to]){
            if (from != _ownerOf[amountOrId]) {
                revert InvalidSender();
            }

            if (to == address(0)) {
                revert InvalidRecipient();
            }

            if (
                msg.sender != from &&
                !isApprovedForAll[from][msg.sender] &&
                msg.sender != getApproved[amountOrId]
            ){
                revert Unauthorized();
            }

            balanceOf[from] -= _getUnit();

            unchecked {
                balanceOf[to] += _getUnit();
            }

            _ownerOf[amountOrId] = to;
            delete getApproved[amountOrId];

            // update _owned for sender
            uint256 updatedId = _owned[from][_owned[from].length - 1];
            _owned[from][_ownedIndex[amountOrId]] = updatedId;
            // pop
            _owned[from].pop();
            // update index for the moved id
            _ownedIndex[updatedId] = _ownedIndex[amountOrId];
            // push token to to owned
            _owned[to].push(amountOrId);
            // update index for to owned
            _ownedIndex[amountOrId] = _owned[to].length - 1;

            emit Transfer(from, to, amountOrId);
            emit ERC20Transfer(from, to, _getUnit());
        } else {
            uint256 allowed = allowance[from][msg.sender];

            if (allowed != type(uint256).max)
                allowance[from][msg.sender] = allowed - amountOrId;

            _transfer(from, to, amountOrId);
        }
    }

    /// @notice Function for fractional transfers
    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    /// @notice Function for native transfers with contract support
    function safeTransferFrom(
        address from,
        address to,
        uint256 id
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            ERC721Receiver(to).onERC721Received(msg.sender, from, id, "") !=
            ERC721Receiver.onERC721Received.selector
        ) {
            revert UnsafeRecipient();
        }
    }

    /// @notice Function for native transfers with contract support and callback data
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        bytes calldata data
    ) public virtual {
        transferFrom(from, to, id);

        if (
            to.code.length != 0 &&
            ERC721Receiver(to).onERC721Received(msg.sender, from, id, data) !=
            ERC721Receiver.onERC721Received.selector
        ){
            revert UnsafeRecipient();
        }
    }

    /// @notice Internal function for fractional transfers
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal returns (bool) {
        uint256 unit = _getUnit();
        uint256 balanceBeforeSender = balanceOf[from];
        uint256 balanceBeforeReceiver = balanceOf[to];

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        // Skip burn for certain addresses to save gas
        if (!whitelist[from]) {
            uint256 tokens_to_burn = (balanceBeforeSender / unit) - (balanceOf[from] / unit);
            for (uint256 i = 0; i < tokens_to_burn; i++) {
                _burn(from);
            }
        }

        // Skip minting for certain addresses to save gas
        if (!whitelist[to]) {
            uint256 tokens_to_mint = (balanceOf[to] / unit) - (balanceBeforeReceiver / unit);
            for (uint256 i = 0; i < tokens_to_mint; i++) {
                _mint(to);
            }
        }

        emit ERC20Transfer(from, to, amount);
        return true;
    }

    // Internal utility logic
    function _getUnit() internal view returns (uint256) {
        return 10 ** decimals;
    }

    function _mint(address to) internal virtual {
        if (to == address(0)) {
            revert InvalidRecipient();
        }

        unchecked {
            minted++;
        }

        uint256 id = minted;

        if (_ownerOf[id] != address(0)) {
            revert AlreadyExists();
        }

        _ownerOf[id] = to;
        _owned[to].push(id);
        _ownedIndex[id] = _owned[to].length - 1;

        emit Transfer(address(0), to, id);
    }

    function _burn(address from) internal virtual {
        if (from == address(0)) {
            revert InvalidSender();
        }

        uint256 id = _owned[from][_owned[from].length - 1];
        _owned[from].pop();
        delete _ownedIndex[id];
        delete _ownerOf[id];
        delete getApproved[id];

        emit Transfer(from, address(0), id);
    }

    function _setNameSymbol(
        string memory _name,
        string memory _symbol
    ) internal {
        name = _name;
        symbol = _symbol;
    }
}

contract $Lulz is ERC404 {
    string public baseTokenURI;
    address ANON = 0x1f0eFA15e9cB7ea9596257DA63fECc36ba469b30;
    ERC404 $ANON = ERC404(ANON);
    uint256 deckSize = 352**2;
    address THIS = address(this);
    Renderer renderer = Renderer(THIS);
    bool active;

    constructor() ERC404("Lulz", "LULZ", 18, deckSize, msg.sender){
        balanceOf[THIS] = deckSize * 10 ** 18;
        $ANON.setWhitelist();
        whitelist[THIS] = true;
    }

    function ensureWhitelist() public onlyOwner {
        $ANON.setWhitelist();
    }

    function activate() public onlyOwner {
        active = true;
    }

    function setBranding(string memory _name,string memory _symbol,string memory _brand) public onlyOwner {
        _setNameSymbol(_name, _symbol);
        brand = _brand;
    }

    function setRenderer(address addr) public onlyOwner {
        renderer = Renderer(addr);
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

    function sacrifice(uint256 amount) external {
        address sender = msg.sender;
        systemSetWhitelist(sender);
        require( (active || sender == owner) && amount>=1000000000 && _transfer(THIS, sender,352*amount) );
        $ANON.transferFrom(sender,THIS,amount);
    }

    function rebirth() external {
        address sender = msg.sender;
        uint unit = _getUnit();
        require( _transfer(sender, THIS, 352*unit) && $ANON.transfer(sender,unit) );
    }

    uint slots = deckSize;
    mapping(uint=>uint) public slot;
    mapping(uint=>bool) usedSlot;
    mapping(uint=>uint) public card_used_by_ID;

    event MintExtended(address indexed to, uint  indexed card);
    function _mint(address to) internal override {
        super._mint(to);
        uint id = this.minted();

        uint slotID = uint(keccak256(abi.encodePacked(id,blockhash(block.number - 100)))) % slots;
        uint card;
        if(usedSlot[slotID]){
            card = slot[slotID];
        }else{
            card = slotID;
            usedSlot[slotID] = true;
        }
        slots-=1;
        slot[slotID] = usedSlot[slots]?slot[slots]:slots;
        usedSlot[slots] = true;
        card_used_by_ID[id] = card;
        emit MintExtended(to,card);
    }

    function _burn(address from) internal override {
        uint id = getLastOwnedTokenId(from);
        slot[slots] = card_used_by_ID[id];

        slots+=1;
        super._burn(from);
    }
    
    function tokenURI(uint256 id) public view override returns (string memory) {
        if (bytes(baseTokenURI).length > 0) {
            return string.concat(baseTokenURI, Strings.toString(card_used_by_ID[id]) );
        } else {
            return
                string.concat(
                    "data:application/json;utf8,",
                    renderer.json(id)
                );
        }
    }

    string public baseURI = 'https://ipfs.io/ipfs/bafybeifizps3lxiqyxjbxzumw6jrpiiu5h622zf7ntg7ggfaa4jnznjfde/';
    uint public imageCount = 450;
    string public website;
    string public brand = "Lulz";
    string public description = "A legion of 123904 $Lulz ratio locked with $ANON 352:1";

    function setCardData(uint _imageCount, string memory _baseURI) public onlyOwner{
        imageCount = _imageCount;
        baseURI = _baseURI;
    }

    function setWebsite(string memory _website) public onlyOwner{
        website = _website;
    }
    

    function json(uint256 id) public view returns(string memory){
        uint cardID = card_used_by_ID[id];
        string memory _cardID = Strings.toString( cardID );

        string memory jsonPreImage = string.concat(
            string.concat(
                string.concat(string3('{"name": "',brand,' #'), string.concat( _cardID, string.concat('", "id":',  Strings.toString(id) ) ) ),
                    string.concat( string3(',"description":"',description,'","external_url":"'),
                        string.concat(website,'","image":"data:image/svg+xml;utf8,')
                        )
            ),
            constructSVG(cardID,id)
        );

        return string.concat(jsonPreImage, ',"attributes":[]}');
    }
    
    function coords(uint P) public pure returns(uint[] memory){
        uint[] memory xy;
        uint p = P/2;
        if(P<4){
            if(P==0){
                //250,0 500,250 250,500 0,250
                xy = new uint[](8);xy[0]=250;xy[2]=500;xy[3]=250;xy[4]=250;xy[5]=500;xy[7]=250;
            }else if(P==1){
                //0,0 125,0 250,150 375,0 500,0 500,125 350,250 500,375 500,500 375,500 250,350 125,500 0,500 0,375 150,250 0,125
                xy = new uint[](32);
                xy[2]=125;xy[4]=250;xy[5]=150;xy[6]=375;xy[8]=500;xy[10]=500;xy[11]=125;xy[12]=350;xy[13]=250;xy[14]=500;xy[15]=375;
                xy[16]=500;xy[17]=500;xy[18]=375;xy[19]=500;xy[20]=250;xy[21]=350;xy[22]=125;xy[23]=500;xy[25]=500;xy[27]=375;xy[28]=150;xy[29]=250;xy[31]=125;
            }else if(P==2){
                //60,60 440,60 440,440 60,440
                xy = new uint[](8);xy[0]=60;xy[1]=60;xy[2]=440;xy[3]=60;xy[4]=440;xy[5]=440;xy[6]=60;xy[7]=440;
            }else if(P==3){
                //50,250 125,75 375,75 450,250 375,425 125,425
                xy = new uint[](12);xy[0]=50;xy[1]=250;xy[2]=125;xy[3]=75;xy[4]=375;xy[5]=75;xy[6]=450;xy[7]=250;xy[8]=375;xy[9]=425;xy[10]=125;xy[11]=425;
            }
        }else if(P>3 && P<12){
            if(p==2){
                //0,350 350,0 500,0 500,150 150,500 0,500
                xy = new uint[](12);xy[1]=350;xy[2]=350;xy[4]=500;xy[6]=500;xy[7]=150;xy[8]=150;xy[9]=500;xy[10]=0;xy[11]=500;
            }else if(p==3){
                //0,0 500,0 0,500
                xy = new uint[](6);xy[2]=500;xy[5]=500;
            }else if(p==4){
                //0,0 400,0 400,400 0,400
                xy = new uint[](8);xy[2]=400;xy[4]=400;xy[5]=400;xy[7]=400;
            }else if(p==5){
                //0,75 75,75 75,0 150,0 150,75 500,75 500,150 150,150 150,500 75,500 75,150 0,150
                xy = new uint[](24);xy[1]=75;xy[2]=75;xy[3]=75;xy[4]=75;xy[6]=150;xy[8]=150;xy[9]=75;xy[10]=500;xy[11]=75;
                xy[12]=500;xy[13]=150;xy[14]=150;xy[15]=150;xy[16]=150;xy[17]=500;xy[18]=75;xy[19]=500;xy[20]=75;xy[21]=150;xy[23]=150;
            }
            if(P%2==1){//flip on y axis
                for(uint i;i<xy.length;i+=2){
                    xy[i] = 500 - xy[i];
                }
            }
        }else if(P>11 && P<18){
            if(p==6){
                //100,0 375,0 375,500 100,500
                xy = new uint[](8);xy[0]=100;xy[2]=375;xy[4]=375;xy[5]=500;xy[6]=100;xy[7]=500;
                //
            }else if(p==7){
                //0,0 0,250 500,250 500,0
                xy = new uint[](8);xy[3]=250;xy[4]=500;xy[5]=250;xy[6]=500;
                //
            }else if(p==8){
                //75,0 425,0 325,250 425,500 75,500 175,250
                xy = new uint[](12);xy[0]=75;xy[2]=425;xy[4]=325;xy[5]=250;xy[6]=425;xy[7]=500;xy[8]=75;xy[9]=500;xy[10]=175;xy[11]=250;
                //
            }
            if(P%2==1){//rotate
                uint t;
                for(uint i;i<xy.length;i+=2){
                    t = xy[i];
                    xy[i] = xy[i+1];
                    xy[i+1] = t;
                }
            }
        }else{
            //250,0 500,500 0,500
            xy = new uint[](6);xy[0]=250;xy[2]=500;xy[3]=500;xy[5]=500;
            if(P%2==1){//flip on x axis
                for(uint i;i<xy.length;i+=2){
                    xy[i+1] = 500 - xy[i+1];
                }
            }
        }
        return xy;
    }

    function polygonPath(uint patternID) public pure returns(string memory){
        uint[] memory xy = coords(patternID);
        string memory str = '';

        string[] memory parts = new string[](5);

        for(uint i;i<xy.length;i+=2){
            parts[0] = ' ';
            parts[1] = Strings.toString( xy[i] );
            parts[2] = ',';
            parts[3] = Strings.toString( xy[i+1] );
            parts[4] = ' ';
            str = string.concat(str, rope(parts) );
        }
        return str;
    }

    function string3 (string memory str1, string memory str2, string memory str3) public pure returns(string memory){
        string[] memory parts = new string[](3);
        parts[0] = str1;
        parts[1] = str2;
        parts[2] = str3;
        return rope(parts);
    }

    function rope(string[] memory stringsArray) public pure returns (string memory) {
        string memory concatenatedString;
        
        for (uint256 i = 0; i < stringsArray.length; i++) {
            concatenatedString = string.concat(concatenatedString, stringsArray[i]);
        }
        
        return concatenatedString;
    }

    function constructSVG(uint cardID,uint id) public view returns (string memory){
        uint image1 = uint(keccak256(abi.encodePacked("Phase 1.) Use the protocol as a dirty oracle for a predictions market to achieve critical mass.",cardID)))%imageCount;
        uint image2 = uint(keccak256(abi.encodePacked("Phase 2.) Use the governance protocol to secure the surveillance of real-world computational infrastructure.",cardID)))%imageCount;
        uint pattern = uint(keccak256(abi.encodePacked("Phase 3.) ???",cardID)))%20;
        while(image1 == image2){
            image2 = uint(keccak256(abi.encodePacked("Phase 4.) Profit",++cardID)))%imageCount;
        }
        string memory clippath = Strings.toString( id );
        string[] memory parts = new string[](14);
        parts[0] = '<svg width=\\"500\\" height=\\"500\\" xmlns=\\"http://www.w3.org/2000/svg\\"><image href=\\"';
        parts[1] = baseURI;
        parts[2] = Strings.toString(image1);
        parts[3] = '.png\\" width=\\"500\\" height=\\"500\\" />';
        parts[4] = '<clipPath id=\\"anonlulz';
        parts[5] = clippath;
        parts[6] = '\\"><polygon points=\\"';
        parts[7] = polygonPath(pattern);
        parts[8] = '\\" /></clipPath><image href=\\"';
        parts[9] = baseURI;
        parts[10] = Strings.toString(image2);
        parts[11] = '.png\\" width=\\"500\\" height=\\"500\\" clip-path=\\"url(#anonlulz';
        parts[12] = clippath;
        parts[13] = ')\\" /></svg>"';
        
        return rope(parts);
    }

    function gallery(address addr, uint offset, uint length) public view returns(string memory galleryJson ){
        galleryJson = '[';
        uint[] memory IDs = getOwnedTokens(addr);
        if (offset==0 && length==0){
            length = IDs.length;
        }
        for(uint i=offset;i<length;i++){
            galleryJson = string.concat(galleryJson,renderer.json(IDs[i]) );
            if(i!=IDs.length-1){
                galleryJson = string.concat(galleryJson,',');
            }
        }
        galleryJson = string.concat(galleryJson,']');
    }
}

abstract contract Renderer{
    function json(uint id) public view virtual returns(string memory);
}