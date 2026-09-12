// Sources flattened with hardhat v2.19.4 https://hardhat.org

// SPDX-License-Identifier: MIT

// File contracts/interfaces/internal/IDecaCollection.sol

pragma solidity ^0.8.17;

struct Recipient {
    address payable recipient;
    uint16 bps;
}

interface IDecaCollection {
    error InvalidTokenId();
    error OnlyCreator();
    error OnlyMinterOrCreator();
    error NotTokenOwnerOrApproved();
    error ERC20SplitFailed();
    error TotalBpsMustBe10000();
    error EthTransferFailed();

    /**
     * @notice Emitted when ETH is transferred.
     * @param account The address of the account which received the ETH.
     * @param amount The amount of ETH transferred.
     */
    event ETHTransferred(address indexed account, uint256 amount);

    /**
     * @notice Emitted when an ERC20 token is transferred.
     * @param erc20Contract The address of the ERC20 contract.
     * @param account The address of the account which received the ERC20.
     * @param amount The amount of ERC20 transferred.
     */
    event ERC20Transferred(address indexed erc20Contract, address indexed account, uint256 amount);

    /**
     * @notice Emitted when the token URI is set on a token.
     * @param tokenId The id of the token.
     * @param tokenURI The token URI of the token.
     */
    event TokenUriSet(uint256 indexed tokenId, string tokenURI);

    /**
     * @notice Emitted when the treasury address is updated.
     * @param treasury The address of the new treasury.
     */
    event TreasuryUpdated(address indexed treasury);

    /**
     * @notice Emitted when the royalty bps is updated.
     * @param royaltyBps The royalty bps.
     */
    event RoyaltyBpsUpdated(uint256 royaltyBps);

    function initialize(
        address factory_,
        address creator_,
        address roleAuthority_,
        string calldata name_,
        string calldata symbol_,
        Recipient[] calldata recipients
    ) external;

    function creator() external view returns (address);

    function exists(uint256 tokenId) external view returns (bool);

    function mint(address to, uint256 tokenId) external;

    function burn(uint256 tokenId) external;

    function mintTimestamps(uint256 tokenId) external view returns (uint256);

    function setRecipients(Recipient[] calldata recipients) external;

    function setTreasuryAddress(address treasury_) external;

    function setRoyaltyBps(uint256 royaltyBps_) external;

    function getRecipients() external view returns (Recipient[] memory);

    function royaltyInfo(uint256, uint256 _salePrice) external view returns (address receiver, uint256 royaltyAmount);
}

// File contracts/deca-collections/libraries/MintStructsV3.sol

pragma solidity ^0.8.17;

/**
 * @title MintStructs
 */
library MintStructsV3 {
    /**
     * @notice Payslip is the struct for a payout on settlement.
     * @dev Payslips are paid out in order, if there is not enough balance to pay out the next payslip, the settlement fails.
     * @param amountInWei Amount to pay out in wei
     * @param recipient Address to pay out to
     */
    struct Payslip {
        address recipient;
        uint256 amountInWei;
    }

    /**
     * @notice ListingInfo is the struct for a taker ask/bid order. It contains the parameters required for a direct purchase.
     * @dev ListingInfo struct is matched against a MintPass struct at the protocol level during settlement.
     * @param nonce Nonce to ensure listing signature is not re-used
     * @param creatorAddress Address of the creator accepting the bid or listing the item
     * @param collectionAddress Address to mint the token on
     * @param tokenId Id of the token to mint
     * @param priceInWei Price to mint the token for
     * @param expiresAt Timestamp the listing expires at
     * @param allowedTakers Array of addresses allowed to take the order
     * @param payslips Array of payslips to be paid out on settlement
     */
    struct ListingInfo {
        uint256 nonce;
        address creatorAddress;
        address collectionAddress;
        uint256 tokenId;
        uint256 priceInWei;
        uint256 expiresAt;
        address[] allowedTakers;
        Payslip[] payslips;
    }

    /**
     * @notice To enable gasless cancellation of listings and bids, we provide a fast expiring signature that is required during settlement and acts as an off-chain mint pass.
     *        If a creator tells Deca they want to cancel their listing/bid acceptance, we mark it as cancelled internally and refuse to provide a signature for settlement.
     *        In case a creator wants to cancel their listing/bid acceptance without going through Deca in case the expiry time isn't short enough, they can do so on chain.
     * @dev listingSignatureHash acts as a nonce, if it's already been used the settlement fails.
     * @param expiresAt Timestamp signature expires at
     * @param listingSignatureHash ListingInfo struct is matched against a MintPass struct at the protocol level during settlement.
     * @param signer Address owned by Deca used to sign the message
     */
    struct MintPass {
        uint256 expiresAt;
        bytes32 listingSignatureHash;
        address signer;
    }

    /**
     * @notice A summary of the settlement data required to mint on demand.
     * @param listingSignature Signature for the listing info
     * @param mintPassSignature Signature for the mint pass
     * @param listing ListingInfo struct, signed by creator
     * @param mintPass MintPass struct, signed by Deca
     */
    struct Settlement {
        bytes listingSignature;
        bytes mintPassSignature;
        ListingInfo listing;
        MintPass mintPass;
    }

    /**
     * @notice CollectionInfo is the struct that provides info about a collection being created.
     * @param signer Address owned by Deca used to sign the message
     * @param nonce Nonce for the collection, used to generate the collection address
     * @param collectionName Name of the collection being created
     * @param collectionSymbol Symbol of the collection being created
     * @param royaltyRecipients Array of secondary market royalty recipients
     */
    struct CollectionInfo {
        string collectionName;
        string collectionSymbol;
        uint96 nonce;
        address signer;
        Recipient[] royaltyRecipients;
    }

    /**
     * @dev This is the type hash constant used to compute the taker order hash.
     */
    bytes32 public constant _LISTINGINFO_TYPEHASH = keccak256(
        "ListingInfo(" "uint256 nonce," "address creatorAddress," "address collectionAddress," "uint256 tokenId,"
        "uint256 priceInWei," "uint256 expiresAt," "address[] allowedTakers," "Payslip[] payslips" ")"
        "Payslip(address recipient,uint256 amountInWei)"
    );

    /**
     * @dev This is the type hash constant used to compute the payslip hash.
     */
    bytes32 public constant _PAYSLIP_TYPEHASH = keccak256("Payslip(" "address recipient," "uint256 amountInWei" ")");

    /**
     * @dev This is the type hash constant used to compute the mint pass hash.
     */
    bytes32 internal constant _MINTPASS_TYPEHASH =
        keccak256("MintPass(" "uint256 expiresAt," "bytes32 listingSignatureHash," "address signer" ")");

    /**
     * @dev This is the type hash constant used to compute the collection info hash.
     */
    bytes32 internal constant _COLLECTIONINFO_TYPEHASH = keccak256(
        "CollectionInfo(" "string collectionName," "string collectionSymbol," "uint96 nonce," "address signer,"
        "Recipient[] royaltyRecipients" ")" "Recipient(address recipient,uint16 bps)"
    );

    /**
     * @dev This is the type hash constant used to compute the recipient hash.
     */
    bytes32 internal constant _RECIPIENT_TYPEHASH = keccak256("Recipient(" "address recipient," "uint16 bps" ")");

    /**
     * @notice This function is used to compute the EIP712 hash for an ListingInfo struct.
     * @param listingInfo ListingInfo struct
     * @return listingInfoHash Hash of the ListingInfo struct
     */
    function hash(ListingInfo memory listingInfo) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _LISTINGINFO_TYPEHASH,
                listingInfo.nonce,
                listingInfo.creatorAddress,
                listingInfo.collectionAddress,
                listingInfo.tokenId,
                listingInfo.priceInWei,
                listingInfo.expiresAt,
                keccak256(abi.encodePacked(listingInfo.allowedTakers)),
                _encodePayslips(listingInfo.payslips)
            )
        );
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a Payslip struct.
     * @param payslip Payslip struct
     * @return payslipHash Hash of the Payslip struct
     */
    function _encodePayslip(Payslip memory payslip) internal pure returns (bytes32) {
        return keccak256(abi.encode(_PAYSLIP_TYPEHASH, payslip.recipient, payslip.amountInWei));
    }

    /**
     * @notice This function is used to compute the EIP712 hash for an array of Payslip structs.
     * @param payslips Array of Payslip structs
     * @return payslipsHash Hash of the Payslip structs
     */
    function _encodePayslips(Payslip[] memory payslips) internal pure returns (bytes32) {
        bytes32[] memory encodedPayslips = new bytes32[](payslips.length);
        for (uint256 i = 0; i < payslips.length; i++) {
            encodedPayslips[i] = _encodePayslip(payslips[i]);
        }

        return keccak256(abi.encodePacked(encodedPayslips));
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a MintPass struct.
     * @param mintPass MintPass struct
     * @return mintPassHash Hash of the MintPass struct
     */
    function hash(MintPass memory mintPass) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(_MINTPASS_TYPEHASH, mintPass.expiresAt, mintPass.listingSignatureHash, mintPass.signer)
        );
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a CollectionInfo struct.
     * @param collectionInfo CollectionInfo struct
     * @return collectionInfoHash Hash of the CollectionInfo struct
     */
    function hash(CollectionInfo memory collectionInfo) internal pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _COLLECTIONINFO_TYPEHASH,
                keccak256(bytes(collectionInfo.collectionName)),
                keccak256(bytes(collectionInfo.collectionSymbol)),
                collectionInfo.nonce,
                collectionInfo.signer,
                _encodeRecipients(collectionInfo.royaltyRecipients)
            )
        );
    }

    /**
     * @notice This function is used to compute the EIP712 hash for a Recipient struct.
     * @param recipient Recipient struct
     * @return recipientHash Hash of the Recipient struct
     */
    function _encodeRecipient(Recipient memory recipient) internal pure returns (bytes32) {
        return keccak256(abi.encode(_RECIPIENT_TYPEHASH, recipient.recipient, recipient.bps));
    }

    /**
     * @notice This function is used to compute the EIP712 hash for an array of Recipient structs.
     * @param recipients Array of Recipient structs
     * @return recipientsHash Hash of the Recipient structs
     */
    function _encodeRecipients(Recipient[] memory recipients) internal pure returns (bytes32) {
        bytes32[] memory encodedRecipients = new bytes32[](recipients.length);
        for (uint256 i = 0; i < recipients.length; i++) {
            encodedRecipients[i] = _encodeRecipient(recipients[i]);
        }

        return keccak256(abi.encodePacked(encodedRecipients));
    }
}

// File contracts/utils/MintStructsHashHelpers.sol

pragma solidity ^0.8.17;

contract MintStructsHashHelpers {
    using MintStructsV3 for MintStructsV3.ListingInfo;

    function getListingId(MintStructsV3.ListingInfo calldata info) public pure returns (bytes32) {
        return info.hash();
    }

    function getListingTypehash() public pure returns (bytes32) {
        return MintStructsV3._LISTINGINFO_TYPEHASH;
    }

    function getPayslipTypehash() public pure returns (bytes32) {
        return MintStructsV3._PAYSLIP_TYPEHASH;
    }
}