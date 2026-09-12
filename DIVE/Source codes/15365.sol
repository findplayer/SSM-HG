// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

library Strings {
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

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Caller is not the owner");
    }

    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
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

abstract contract ERC165 is IERC165 {
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// Interface for interacting with the CryptoPunksMarket contract
interface ICryptoPunksMarket {
    function punkIndexToAddress(uint256 punkIndex) external view returns (address);
    function balanceOf(address _owner) external view returns (uint256);
}

// PunkedCoins contract inheriting from ERC165 for interface detection and Ownable for ownership management
contract PunkedCoins is ERC165, Ownable {
    // External interface used for interacting with the CryptoPunksMarket contract
    ICryptoPunksMarket private _cryptoPunksMarket;
    
    // Constants defining key parameters for ERC721 interface IDs
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    
    uint256 private constant _MASTER_BALANCE = 10000;           // Total supply of master tokens (inherited from CryptoPunks) 
    uint256 private constant _MINT_COOLDOWN = 30 days;          // Cooldown period between minting actions
    uint256 private constant _PRICE_INCREMENT = 0.02 ether;     // Price increment for unsealing tokens

    string private _gateway;        // Base URI for token metadata
    string private _masterCID;      // Content identifier for Mater token metadata
    string private _sealedCID;      // Content identifier for sealed Mater token metadata
    string private _instanceCID;    // Content identifier for individual token metadata

    uint256 private _currentIndex = 10000;      // Tracks the current token index for minting
    uint256 private _unsealPrice = 0.1 ether;   // Initial price to unseal a token

    mapping(uint256 => address) private _tokenOwner;                            // Token ID to owner address
    mapping(address => uint256) private _ownedTokensCount;                      // Owner address to token count
    mapping(uint256 => address) private _tokenApprovals;                        // Token ID to approved address
    mapping(address => mapping(address => bool)) private _operatorApprovals;    // Owner to operator approvals
    mapping(uint256 => uint256) private _tokenMaster;                           // Token ID to its master token ID
    mapping(uint256 => uint256) private _lastMintTime;                          // Token ID to last mint time for cooldown management
    mapping(uint256 => bool) private _sealed;                                   // Token ID to sealed status

    // Events for marketplace synchronization
    event Locked(uint256 tokenId);
    event MetadataUpdate(uint256 _tokenId);
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    // Event for logging all Ether transactions within the contract
    event EtherTransaction(address indexed sender, address indexed receiver, uint256 amount, string transactionType);

    // ERC721 events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // Contract constructor
    constructor(address _cryptoPunksMarketAddress) {
        _cryptoPunksMarket = ICryptoPunksMarket(_cryptoPunksMarketAddress);
    }

    // Administrative functions
    function setGateway(string memory newGateway) public onlyOwner {
        _gateway = newGateway;
    }

    function setCID(string memory masterCID, string memory sealedCID, string memory instanceCID) public onlyOwner {
        _masterCID = masterCID;
        _sealedCID = sealedCID;
        _instanceCID = instanceCID;
    }

    function broadcastBatchMetadataUpdate(uint256 fromTokenId, uint256 toTokenId) public onlyOwner {
        emit BatchMetadataUpdate(fromTokenId, toTokenId);
    }  

    function initOwnershipStatus(uint256 fromTokenId, uint256 toTokenId) public onlyOwner {
        require(isMaster(toTokenId), "Non existent token");        
        for (uint256 tokenId = fromTokenId; tokenId <= toTokenId; tokenId++) {
            emit Transfer(address(0), address(0), tokenId);
        }
    }

    // ERC721, ERC721Metadata
    function name() public pure returns (string memory) {
        return "Punked Coin";
    }

    function symbol() public pure returns (string memory) {
        return "PCN";
    }

    function balanceOf(address owner) public view returns (uint256) {
        return _ownedTokensCount[owner] + _cryptoPunksMarket.balanceOf(owner) ;
    }

    function ownerOf(uint256 tokenId) public view returns (address owner) {
        if (isMaster(tokenId))
            owner =  _ownerOfMaster(tokenId);
        else
            owner = _tokenOwner[tokenId];
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        require(isMaster(tokenId) || _exists(tokenId), "Non existent token");

        string memory cid;
        if (isMaster(tokenId)) {
            cid = _sealed[tokenId] ? _sealedCID : _masterCID;
        } else {
            cid = _instanceCID;
        }

        string memory template = isMaster(tokenId) ? Strings.toString(tokenId) : Strings.toString(_tokenMaster[tokenId]);

        return string(abi.encodePacked(_gateway, cid, "/", template, ".json"));
    }

    // Token approval and transfer
    function approve(address to, uint256 tokenId) public {
        require(!isMaster(tokenId), "Cannot approve master");
        address owner = ownerOf(tokenId);
        require(to != owner, "Approval to current owner");
        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "Caller is not owner nor approved for all");

        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) public view returns (address) {
        require(!isMaster(tokenId), "Cannot approve master");
        require(_exists(tokenId), "Non existent token");
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) public {
        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    function isApprovedForAll(address owner, address operator) public view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) public {
        _transfer(from, to, tokenId);        
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) public {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "Transfer to non ERC721Receiver implementer");
    }

    // Emits events to simulate the minting process for Master tokens.
    // This method is used for external platforms to recognize token ownership without altering any state.
    function broadcastCoinOwnershipStatus(uint256 tokenId) public {
        require(isMaster(tokenId), "Token is not master");        

        // Emit a Transfer event from a 0 address to the owner to mimic the minting process
        emit Transfer(address(0), _ownerOfMaster(tokenId), tokenId);
        // Emit the Locked event to indicate that the token is not tradable on marketplaces.
        emit Locked(tokenId);
    }    

    // Minting and sealing
    function mint(uint256 masterId) external {
        require(canMint(masterId), "Can not be minted");
        require(_ownerOfMaster(masterId) == _msgSender(), "Caller is not the owner");
        require(!_isContract(_msgSender()), "Only EOAs can mint");

        _mint(_msgSender(), _currentIndex);
        _tokenMaster[_currentIndex] = masterId;
        _lastMintTime[masterId] = block.timestamp;

        unchecked {
            _currentIndex += 1;
        }        

        // Seal master on every 5th token or 25% randomness
        _sealed[masterId] = _currentIndex % 5 == 0 || _random() % 4 == 0;
        emit MetadataUpdate(masterId);
    }

    function unseal(uint256 tokenId) public payable {
        require(_sealed[tokenId], "Token is not sealed");
        require(msg.value == _unsealPrice, "Exact payment required"); 
        require(!_isContract(_msgSender()), "Only EOAs can unseal");

        // Unseal the token
        _sealed[tokenId] = false;
        unchecked {
            _unsealPrice += _PRICE_INCREMENT;
        }

        emit MetadataUpdate(_tokenMaster[_currentIndex]);
        emit EtherTransaction(msg.sender, address(this), msg.value, "Unsealed");        
    }    

    function unsealPrice() public view returns (uint256) {
        return _unsealPrice;
    }    

    function canMint(uint256 masterId) public view returns (bool) {
        return !isSealed(masterId) && block.timestamp >= getNextMintTime(masterId);
    }
        
    function isMaster(uint256 tokenId) public pure returns (bool) {
        return tokenId < _MASTER_BALANCE;
    }  

    function isSealed(uint256 masterId) public view returns (bool) {
        require(isMaster(masterId), "Invalid masterId");
        return _sealed[masterId];
    }    

    function getNextMintTime(uint256 masterId) public view returns (uint256) {
        return _lastMintTime[masterId] + _MINT_COOLDOWN;
    }

    // Private and internal utility functions
    function _ownerOfMaster(uint256 masterId) private view returns (address) {
        // Obtain the owner address from the CryptoPunksMarket contract
        return _cryptoPunksMarket.punkIndexToAddress(masterId);
    }

    function _exists(uint256 tokenId) private view returns (bool) {
        return _tokenOwner[tokenId] != address(0);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        require(_exists(tokenId), "Non existent token");

        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "Mint to the zero address");
        require(!_exists(tokenId), "Token already minted");

        unchecked {
            _ownedTokensCount[to] += 1;
        }
        _tokenOwner[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
        emit MetadataUpdate(tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(!isMaster(tokenId), "Cannot transfer master");
        require(_isApprovedOrOwner(_msgSender(), tokenId), "Caller is not owner nor approved");        
        require(ownerOf(tokenId) == from, "Transfer from incorrect owner");

        // Clear approvals from the previous owner
        approve(address(0), tokenId);

        unchecked {
            _ownedTokensCount[from] -= 1;
            _ownedTokensCount[to] += 1;
        }
        _tokenOwner[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }


    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly { size := extcodesize(account) }
        return size > 0;
    }    

    function _random() private view returns (uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, blockhash(block.number - 1), _msgSender())));
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data) private returns (bool) {
        if (_isContract(to)) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver.onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("Transfer to non ERC721Receiver implementer");
                } else {
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    // Withdrawal function for contract owner
    function withdrawAll() public onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "No Ether left to withdraw");

        (bool success, ) = owner().call{value: amount}("");
        require(success, "Transfer failed");
 
        emit EtherTransaction(address(this), owner(), amount, "Withdrawal");
    }     

    // Fallback and receive functions
    receive() external payable {
        emit EtherTransaction(msg.sender, address(this), msg.value, "Received");
    }

    fallback() external payable {
        emit EtherTransaction(msg.sender, address(this), msg.value, "Received");
    }

    // ERC165 Compliance
    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return interfaceId == _INTERFACE_ID_ERC721
            || interfaceId == _INTERFACE_ID_ERC721_METADATA
            || super.supportsInterface(interfaceId);
    }	
}