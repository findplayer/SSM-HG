/**
 * @title 404-B Dynamic Standard Token
 * @dev Combines features of ERC-20 and ERC-721 standards into a single contract with enhanced functionality.
 *      The 404-B token standard allows for dynamic updates to token attributes and rules, facilitating full decentralization.
 *      This hybrid approach enables communities to adjust token specifications dynamically, supporting both fungible (ERC-20-like) and 
 *      non-fungible (ERC-721-like) properties in a unified framework.
 */
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract DYNAMIC404 {
    string internal _name = "404-B Dynamic Name";
    string internal _symbol = "404-B Dynamic Symbol";
    uint internal _totalSupply = 6900 * 10**6;
    uint internal _decimals = 6;
    uint one = 10**6; 
    uint cent = 10**4;
    string public baseTokenURI = "404-B Dynamic Base URI";
    address public dev;
    address[3] public pairs;
    mapping(address => uint) internal _balanceOf;
    mapping(address => mapping(address => uint)) internal _allowance;
    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(address => uint16[]) public ownedNFTs;

    event Transfer(address indexed from, address indexed to, uint indexed tokenId);
    event ERC20Transfer(address indexed from, address indexed to, uint amount);
    event Approval(address indexed owner, address indexed spender, uint256 indexed amount, uint256 id);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    event BaseTokenURIChanged(string newBaseTokenURI);
    event BNAME(string newName);
    event BSYMBOL(string newSymbol);

    modifier onlyDev() {require(msg.sender == dev, "Not the dev");_;}

    constructor() {
        _balanceOf[msg.sender] = _totalSupply; 
        dev = msg.sender;
    }

    function name() public view returns (string memory) { return _name; }
    function symbol() public view returns (string memory) { return _symbol; }
    function decimals() public view returns (uint) { return _decimals; }
    function totalSupply() public view returns (uint) { return _totalSupply; }
    function balanceOf(address account) public view returns (uint) { return _balanceOf[account]; }
    function allowance(address owner, address spender) public view returns (uint) { return _allowance[owner][spender]; }

    function setPairs(address pair1, address pair2, address pair3) public onlyDev {
        pairs[0] = pair1;
        pairs[1] = pair2;
        pairs[2] = pair3;
    }

    function approve(address spender, uint amount) public returns (bool) {
        if (amount > one) {
            _allowance[msg.sender][spender] = amount;
            setApprovalForAll(spender, true);
            emit Approval(msg.sender, spender, amount, 0);
        } else {
            address owner = ownerOf[amount];
            if (msg.sender != owner && !isApprovedForAll(owner, msg.sender)) revert("Unauthorized");
            _tokenApprovals[amount] = spender;
            emit Approval(owner, spender, one, uint16(amount));
        }
        return true;
    }

    function _transfer20(address from, address to, uint amount) internal {
        require(_balanceOf[from] >= amount, "transfer amount exceeds balance");
        _balanceOf[from] -= amount;
        _balanceOf[to] += amount;
        emit ERC20Transfer(from, to, amount);
    }

    function _transfer721(address from, address to, uint tokenId) internal {
        bool isFromPair = from == pairs[0] || from == pairs[1] || from == pairs[2];
        require(
            from == ownerOf[tokenId] || 
            (isFromPair && (msg.sender == getApproved(tokenId) || isApprovedForAll(ownerOf[tokenId], msg.sender))),
            "transfer not allowed"
        );

        delete _tokenApprovals[tokenId];
        ownerOf[tokenId] = to;
        for (uint i = 0; i < ownedNFTs[from].length; i++) {
            if (ownedNFTs[from][i] == tokenId) {
                ownedNFTs[from][i] = ownedNFTs[from][ownedNFTs[from].length - 1];
                ownedNFTs[from].pop();
                break;
            }
        }
        ownedNFTs[to].push(uint16(tokenId));
        emit Transfer(from, to, tokenId);
    }

        // Function to facilitate both ERC20 and ERC721 transfers
    function transfer(address to, uint amount) public returns (bool) {
        if (amount >= cent) {
            _transfer20(msg.sender, to, amount);
        } else {
            _transfer721(msg.sender, to, amount);
            _balanceOf[msg.sender] -= one; 
            _balanceOf[to] += one; 
        }
        return true;
    }

    function transferFrom(address from, address to, uint amount) public returns (bool) {
        if (amount >= cent) { // Considered as ERC20 transfer
            require(_allowance[from][msg.sender] >= amount, "transfer amount exceeds allowance");
            _spendAllowance(from, msg.sender, amount);
            _transfer20(from, to, amount);
        } else { // Considered as ERC721 transfer
            require(
                from == ownerOf[amount] &&
                (msg.sender == from || msg.sender == getApproved(amount) || isApprovedForAll(from, msg.sender)),
                "transfer not allowed"
            );
            _transfer721(from, to, amount);
            _balanceOf[from] -= one; 
            _balanceOf[to] += one; 
        }
        return true;
    }
    

    function change404Bname(string memory newName) public {
    
        _name = newName;
        emit BNAME(newName);
    }

    function change404BSymbol(string memory newSymbol) public onlyDev {
    _symbol = newSymbol;
    emit BSYMBOL(newSymbol); 
}


    function BBaseURI(string memory newBaseTokenURI) public {
     
        baseTokenURI = newBaseTokenURI;
        emit BaseTokenURIChanged(newBaseTokenURI);
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(ownerOf[tokenId] != address(0), "URI query for nonexistent token");
        return string(abi.encodePacked(baseTokenURI, "/", toString(tokenId)));
    }

    function _spendAllowance(address owner, address spender, uint amount) internal {
        require(_allowance[owner][spender] >= amount, "insufficient allowance");
        _allowance[owner][spender] -= amount;
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(ownerOf[tokenId] != address(0), "Token does not exist");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }


    function toString(uint256 value) internal pure returns (string memory) {

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
            buffer[digits] = bytes1(uint8(48 + value % 10));
            value /= 10;
        }
        return string(buffer);
    }
}