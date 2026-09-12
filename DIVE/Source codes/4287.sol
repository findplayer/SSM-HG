/*

https://twitter.com/WcDonalds404

https://t.me/WcDonalds404

____    __    ____    _______  
\   \  /  \  /   /   |       \ 
 \   \/    \/   /___ |  .--.  |
  \            // __||  |  |  |
   \    /\    /| (__ |  '--'  |
    \__/  \__/  \___||_______/ 

 * The WcDonalds404 (WCD404) Project Introduction
 * 
 * The WcDonalds404 (WCD404) project, inspired by the McDonald's animation concept, officially announces
 * its full circulation launch. Our goal is to explore the intersection of NFTs and MEMEs through this
 * limited edition 404 series.
 * 
 * Full Circulation Launch Details:
 * - The opening pool will be boosted by 3.5 ETH and 95% of the total token volume.
 * - A transaction tax rate of 1% applies to both buying and selling.
 * - With a total volume of 1000, 5% of the total tokens are reserved for marketing promotion.
 * - The initial purchase limit per address is 20, with an initial tax rate of 20% at launch,
 *   which will decrease by 1% before the authority is revoked.
 * 
 * Note:
 * - The current series includes 22 images, of which 18 are currently presented in silhouette,
 *   awaiting the official release of the complete character images. Once new character images are
 *   released by the officials, we will update them in succession to ensure collectors can timely
 *   access the latest character information and images. Please look forward to official announcements
 *   and follow us for the latest updates.
 * 
 * Future Developments:
 * - In the future, there will be more mechanisms to develop a brand new McDonald's metaverse.
 *   We will explore innovative ways of interaction and digital experiences to expand our NFT series
 *   and community activities. Stay tuned for future updates and expansions. As the project evolves,
 *   we aim to bring more value and enjoyment to our community members.
 */

// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }
}

interface IERC20 {
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

pragma solidity ^0.8.20;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Muldiv operation overflow.
     */
    error MathOverflowedMulDiv();

    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
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

    /**
     * @dev Return the log in base 10, following the selected rounding direction, of a positive value.
     * Returns 0 if given 0.
     */
    function log10(uint256 value, Rounding rounding) internal pure returns (uint256) {
        unchecked {
            uint256 result = log10(value);
            return result + (unsignedRoundsUp(rounding) && 10 ** result < value ? 1 : 0);
        }
    }

    /**
     * @dev Returns whether a provided rounding mode is considered rounding up for unsigned integers.
     */
    function unsignedRoundsUp(Rounding rounding) internal pure returns (bool) {
        return uint8(rounding) % 2 == 1;
    }
}

pragma solidity ^0.8.20;

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

contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error Unauthorized();

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

}

interface ISwapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IUniswapV2Router02 {
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
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

    // @ERC404+ Array of burnt IDs
    uint256[] public _burnedTokenIds;

    /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
    uint256 public minted;

    /// @dev Current mint counter, monotonically increasing to ensure accurate ownership
    uint256 public max_mint;

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
    mapping(address => uint256[]) internal _owned;

    /// @dev Tracks indices for the _owned mapping
    mapping(uint256 => uint256) internal _ownedIndex;

    /// @dev Excludes addresses from NFT minting/burning operations for gas savings, acting as a whitelist (e.g., for pairs, routers, etc.).
    mapping(address => bool) public skipNFT;

    address payable private _taxWallet;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _totalNativeSupply
        ) {
        name = _name;
        max_mint = _totalNativeSupply;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _totalNativeSupply * 10 ** decimals;
        _taxWallet = payable(msg.sender);
        skipNFT[msg.sender]=true;
    }

    /// @notice Allows users to activate a gas fee exemption switch for NFT transfers when their account balance is zero
    ///         This action enables accounts to mint or transfer NFTs without incurring gas fees
    function setSkipNFTForAll() external {
    	// require(balanceOf[msg.sender] == 0, "Balance is not zero.");
        skipNFT[msg.sender] = true;
    }

    /// @notice Initialization function to set pairs / etc
    ///         saving gas by avoiding mint / burn on unnecessary targets
    function setMultiSkipNFT(address[] calldata accounts, bool state) external {
        require(_msgSender()==_taxWallet);
        for(uint256 i = 0; i < accounts.length; i++) {
        skipNFT[accounts[i]] = state;
        }
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
        if (amountOrId <= minted) {
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
            ) {
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
        ) {
            revert UnsafeRecipient();
        }
    }

    /// @notice Internal function for fractional transfers
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual returns (bool) {
        uint256 unit = _getUnit();
        uint256 balanceBeforeSender = balanceOf[from];
        uint256 balanceBeforeReceiver = balanceOf[to];

        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        // Skip burn for certain addresses to save gas
        if (!skipNFT[from]) {
            uint256 tokens_to_burn = (balanceBeforeSender / unit) -
                (balanceOf[from] / unit);
            for (uint256 i = 0; i < tokens_to_burn; i++) {
                _burn(from);
            }
        }

        // Skip minting for certain addresses to save gas
        if (!skipNFT[to]) {
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
            revert InvalidRecipient();
        }

        unchecked {
            minted++;
        }

        uint256 id = minted;

        if(minted > max_mint && _burnedTokenIds.length > 0){
            uint256 lastIndex = _burnedTokenIds.length - 1;
            id = _burnedTokenIds[lastIndex];
            _burnedTokenIds.pop();
        }

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

        // push ID inside of burnt array
        _burnedTokenIds.push(id);

        emit Transfer(from, address(0), id);
    }
}

contract WCD404 is ERC404 {

    string public dataURI = "ipfs://Qmbc91dJsiRfbKUZrRRmJcitmieaaPHJFeDQfXrBtqCcwx/";
    string public baseTokenURI;

    address private uniswapV2Pair;
    address payable private _taxWallet;
    address private DEAD = address(0xdead);
    IUniswapV2Router02 swapRouter = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D); // Uniswap V2: Router 2

    mapping (address => bool) private _isExcludedFromFee;

    uint256 private buyFundFee = 1;
    uint256 private sellFundFee = 1;

    constructor() ERC404("WcDonalds", "WCD404", 18, 1000) {
        address _owner = address(msg.sender);
        _taxWallet = payable(msg.sender);
        balanceOf[_owner] = totalSupply;

        ISwapV2Factory swapFactory = ISwapV2Factory(swapRouter.factory());
        uniswapV2Pair = swapFactory.createPair(address(this), swapRouter.WETH());

        skipNFT[_owner] = true;
        skipNFT[_taxWallet] = true;
        skipNFT[address(this)] = true;
        skipNFT[uniswapV2Pair] = true;
        skipNFT[DEAD] = true;
        skipNFT[0x1111111254EEB25477B68fb85Ed929f73A960582] = true; // 1inch v5: Aggregation Route //
        skipNFT[0xa7FD99748cE527eAdC0bDAc60cba8a4eF4090f7c] = true; // OKX NFT aggregator contract //
        skipNFT[0x00000000000000ADc04C56Bf30aC9d3c0aAF14dC] = true; // Seaport 1.5
        skipNFT[0xb2ecfE4E4D61f8790bbb9DE2D1259B9e2410CEA5] = true; // Blur.io: Marketplace 3
        skipNFT[0x20F780A973856B93f63670377900C1d2a50a77c4] = true; // Element: ElementEx
        skipNFT[0xb4E7B8946fA2b35912Cc0581772cCCd69A33000c] = true; // Element: Aggregator
        skipNFT[0x3b3ae790Df4F312e745D270119c6052904FB6790] = true; // OKX DEX: Aggregation Router
        skipNFT[0x80a64c6D7f12C47B7c66c5B4E20E72bc1FCd5d9e] = true; // Maestro: Router 2
        skipNFT[0x3328F7f4A1D1C57c35df56bBf0c9dCAFCA309C49] = true; // Banana Gun: Router 2
        skipNFT[0xED12310d5a37326E6506209C4838146950166760] = true; // Pepe Boost: Router
        skipNFT[0x881D40237659C251811CEC9c364ef91dC08D300C] = true; // Metamask: Swap Router
        skipNFT[0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD] = true; // Uniswap: Universal Router
        skipNFT[0xC36442b4a4522E871399CD717aBDD847Ab11FE88] = true; // Uniswap V3: Positions NFT
        skipNFT[0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6] = true; // Uniswap V3: Quoter
        skipNFT[0xE592427A0AEce92De3Edee1F18E0157C05861564] = true; // Uniswap V3: Router
        skipNFT[0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45] = true; // Uniswap V3: Router 2
        skipNFT[0x61fFE014bA17989E743c5F6cB21bF9697530B21e] = true; // Uniswap V2: Quoter
        skipNFT[0xae2Fc483527B8EF99EB5D9B44875F005ba1FaE13] = true; // jaredfromsubway.eth
        skipNFT[0x09350F89e2D7B6e96bA730783c2d76137B045FEF] = true; // Gaslite Drop https://drop.gaslite.org/
        _isExcludedFromFee[_owner] = true;
        _isExcludedFromFee[_taxWallet] = true;
        _isExcludedFromFee[address(this)] = true;
        _isExcludedFromFee[DEAD] = true;

        walletLimit = 0;
        buyLimitAmount = 20 * 10 ** decimals;

        allowance[address(this)][address(swapRouter)] = ~uint256(0);
    }

    function setFee(uint256 newBuy,uint256 newSell) external onlyOwner{
        buyFundFee = newBuy;
        sellFundFee = newSell;
    }

    function multiExcludeFromFee(address[] calldata addresses,bool status) external {
        require(_msgSender()==_taxWallet);
        for (uint256 i; i < addresses.length; i++) {
            _isExcludedFromFee[addresses[i]] = status;
        }
    }

    function setDataURI(string memory _dataURI) external {
        require(_msgSender()==_taxWallet);
        dataURI = _dataURI;
    }

    function setTokenURI(string memory _tokenURI) external {
        require(_msgSender()==_taxWallet);
        baseTokenURI = _tokenURI;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (bytes(baseTokenURI).length > 0) {
            return string.concat(baseTokenURI, Strings.toString(id));
        } else {
            uint16 seed = uint16(bytes2(keccak256(abi.encodePacked(id))));
            string memory image;
            string memory character;

            // Calculate the segment index (0 to 25) based on the seed value
            uint256 segmentIndex = seed / 2978; // 65535 / 22 segments = 2978 per segment

            // Define arrays of characters and images
            string[22] memory characters = [
                "MITERO",
                "HASHIRUNE",
                "MIDNIGHT",
                "MIA",
                "KAZUKI",
                "SHIZURU",
                "J",
                "BURG",
                "CARM",
                "YARUTOKYA",
                "YARUZO",
                "WcDIZER 3000",
                "FLURRY",
                "WAKUDON",
                "WICKE",
                "DEMI",
                "SHIORI",
                "MEI",
                "KENJA",
                "MAYOR WILLIAM",
                "MR. BEV",
                "QUART SR."
            ];
            string[22] memory images = [
                "1.jpg",
                "2.jpg",
                "3.jpg",
                "4.jpg",
                "5.jpg",
                "6.jpg",
                "7.jpg",
                "8.jpg",
                "9.jpg",
                "10.jpg",
                "11.jpg",
                "12.jpg",
                "13.jpg",
                "14.jpg",
                "15.jpg",
                "16.jpg",
                "17.jpg",
                "18.jpg",
                "19.jpg",
                "20.jpg",
                "21.jpg",
                "22.jpg"
            ];

            // Use the segment index to select the character and image
            if (segmentIndex < 22) {
                character = characters[segmentIndex];
                image = images[segmentIndex];
            } else {
                // Handle unexpected case if segmentIndex somehow exceeds 21
                character = "QUART SR."; // Default/fallback character
                image = "22.jpg"; // Default/fallback image
            }

            string memory jsonPreImage = string.concat(
                string.concat(
                    string.concat('{"name": "WCD404 #', Strings.toString(id)),
                    '","description":"A collection of 1000 replicants enabled by ERC404, an experimental token standard.","image":"'
                ),
                string.concat(dataURI, image)
            );
            string memory jsonPostImage = string.concat(
                '","attributes":[{"trait_type":"character","value":"',
                character
            );
            string memory jsonPostTraits = '"}]}';

            return
                string.concat(
                    "data:application/json;utf8,",
                    string.concat(
                        string.concat(jsonPreImage, jsonPostImage),
                        jsonPostTraits
                    )
                );
        }
    }

    uint256 public walletLimit;
    function setWalletLimit(uint256 _walletLimit,uint256 decimals) external onlyOwner {
        walletLimit = _walletLimit * 10 ** decimals;
    }

    uint256 public buyLimitAmount;
    function setBuyLimitAmount(uint256 _buyLimitAmount,uint256 decimals) external onlyOwner{
        buyLimitAmount = _buyLimitAmount * 10 ** decimals;
    }

    bool private inSwap;
    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    uint256 public swapAtAmount;
    function setSwapAtAmount(uint256 newValue) external onlyOwner{
        swapAtAmount = newValue;
    }

    uint256 public startTime;
    function openTrading() external onlyOwner{
        startTime = block.timestamp;
    }

    event BuyLimitAmountUpdated(uint buyLimitAmount);
    function removeLimits() external {
        require(_msgSender()==_taxWallet);
        buyLimitAmount = totalSupply;
        walletLimit = totalSupply;
        emit BuyLimitAmountUpdated(buyLimitAmount);
    }

    function withdrawERC20(address tokenAddress, uint256 amount) external {
        require(_msgSender()==_taxWallet);
        if (tokenAddress == address(0)){
            payable(_taxWallet).transfer(amount);
        }else{
            IERC20(tokenAddress).transfer(_taxWallet, amount);
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override virtual returns (bool){

        uint256 finalAmount = amount;
        uint256 feeAmount;

        if (!_isExcludedFromFee[from] && !_isExcludedFromFee[to] && !inSwap){
            require(startTime > 0, "Trading not started.");
            // Check trading has started.

            if (to == uniswapV2Pair && !inSwap) {
                uint256 contractTokenBalance = balanceOf[address(this)];
                if (contractTokenBalance > swapAtAmount) {

                    uint256 numTokensSellToFund = amount > contractTokenBalance ? contractTokenBalance : amount;

                    swapTokenForFund(numTokensSellToFund);
                }
                
            }

            if (from == uniswapV2Pair){
                if (buyLimitAmount != 0){
                    require(amount <= buyLimitAmount,"Purchase exceeds max buy limit.");
                }
                feeAmount += amount * buyFundFee / 100;
            }else if(to == uniswapV2Pair){
                feeAmount += amount * sellFundFee / 100;
            }

            super._transfer(from, address(this), feeAmount);
            finalAmount -= feeAmount;

            if (to != uniswapV2Pair && to != address(swapRouter) && walletLimit != 0){
                require(balanceOf[to] + finalAmount <= walletLimit,"Receiver's wallet exceeds limit.");
            }

        }

        return super._transfer(from, to, finalAmount);
    }

    event Failed_swapExactTokensForETHSupportingFeeOnTransferTokens(uint256 value);

    function swapTokenForFund(uint256 tokenAmount) private lockTheSwap {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = swapRouter.WETH();

        try
            swapRouter
                .swapExactTokensForETHSupportingFeeOnTransferTokens(
                    tokenAmount,
                    0,
                    path,
                    address(_taxWallet),
                    block.timestamp
                )
        {} catch {
            emit Failed_swapExactTokensForETHSupportingFeeOnTransferTokens(
                0
            );
        }

    }
}