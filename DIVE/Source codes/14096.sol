// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

type Id is bytes32;

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

/// @dev Warning: For `feeRecipient`, `supplyShares` does not contain the accrued shares since the last interest
/// accrual.
struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}

/// @dev Warning: `totalSupplyAssets` does not contain the accrued interest since the last interest accrual.
/// @dev Warning: `totalBorrowAssets` does not contain the accrued interest since the last interest accrual.
/// @dev Warning: `totalSupplyShares` does not contain the additional shares accrued by `feeRecipient` since the last
/// interest accrual.
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

/// @dev This interface is used for factorizing IMorphoStaticTyping and IMorpho.
/// @dev Consider using the IMorpho interface instead of this one.
interface IMorphoBase {
    /// @notice The EIP-712 domain separator.
    /// @dev Warning: Every EIP-712 signed message based on this domain separator can be reused on another chain sharing
    /// the same chain id because the domain separator would be the same.
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /// @notice The owner of the contract.
    /// @dev It has the power to change the owner.
    /// @dev It has the power to set fees on markets and set the fee recipient.
    /// @dev It has the power to enable but not disable IRMs and LLTVs.
    function owner() external view returns (address);

    /// @notice The fee recipient of all markets.
    /// @dev The recipient receives the fees of a given market through a supply position on that market.
    function feeRecipient() external view returns (address);

    /// @notice Whether the `irm` is enabled.
    function isIrmEnabled(address irm) external view returns (bool);

    /// @notice Whether the `lltv` is enabled.
    function isLltvEnabled(uint256 lltv) external view returns (bool);

    /// @notice Whether `authorized` is authorized to modify `authorizer`'s positions.
    /// @dev Anyone is authorized to modify their own positions, regardless of this variable.
    function isAuthorized(address authorizer, address authorized) external view returns (bool);

    /// @notice The `authorizer`'s current nonce. Used to prevent replay attacks with EIP-712 signatures.
    function nonce(address authorizer) external view returns (uint256);

    /// @notice Sets `newOwner` as `owner` of the contract.
    /// @dev Warning: No two-step transfer ownership.
    /// @dev Warning: The owner can be set to the zero address.
    function setOwner(address newOwner) external;

    /// @notice Enables `irm` as a possible IRM for market creation.
    /// @dev Warning: It is not possible to disable an IRM.
    function enableIrm(address irm) external;

    /// @notice Enables `lltv` as a possible LLTV for market creation.
    /// @dev Warning: It is not possible to disable a LLTV.
    function enableLltv(uint256 lltv) external;

    /// @notice Sets the `newFee` for the given market `marketParams`.
    /// @dev Warning: The recipient can be the zero address.
    function setFee(MarketParams memory marketParams, uint256 newFee) external;

    /// @notice Sets `newFeeRecipient` as `feeRecipient` of the fee.
    /// @dev Warning: If the fee recipient is set to the zero address, fees will accrue there and will be lost.
    /// @dev Modifying the fee recipient will allow the new recipient to claim any pending fees not yet accrued. To
    /// ensure that the current recipient receives all due fees, accrue interest manually prior to making any changes.
    function setFeeRecipient(address newFeeRecipient) external;

    /// @notice Creates the market `marketParams`.
    /// @dev Here is the list of assumptions on the market's dependencies (tokens, IRM and oracle) that guarantees
    /// Morpho behaves as expected:
    /// - The token should be ERC-20 compliant, except that it can omit return values on `transfer` and `transferFrom`.
    /// - The token balance of Morpho should only decrease on `transfer` and `transferFrom`. In particular, tokens with
    /// burn functions are not supported.
    /// - The token should not re-enter Morpho on `transfer` nor `transferFrom`.
    /// - The token balance of the sender (resp. receiver) should decrease (resp. increase) by exactly the given amount
    /// on `transfer` and `transferFrom`. In particular, tokens with fees on transfer are not supported.
    /// - The IRM should not re-enter Morpho.
    /// - The oracle should return a price with the correct scaling.
    /// @dev Here is a list of properties on the market's dependencies that could break Morpho's liveness properties
    /// (funds could get stuck):
    /// - The token can revert on `transfer` and `transferFrom` for a reason other than an approval or balance issue.
    /// - A very high amount of assets (~1e35) supplied or borrowed can make the computation of `toSharesUp` and
    /// `toSharesDown` overflow.
    /// - The IRM can revert on `borrowRate`.
    /// - A very high borrow rate returned by the IRM can make the computation of `interest` in `_accrueInterest`
    /// overflow.
    /// - The oracle can revert on `price`. Note that this can be used to prevent `borrow`, `withdrawCollateral` and
    /// `liquidate` from being used under certain market conditions.
    /// - A very high price returned by the oracle can make the computation of `maxBorrow` in `_isHealthy` overflow, or
    /// the computation of `assetsRepaid` in `liquidate` overflow.
    /// @dev The borrow share price of a market with less than 1e4 assets borrowed can be decreased by manipulations, to
    /// the point where `totalBorrowShares` is very large and borrowing overflows.
    function createMarket(MarketParams memory marketParams) external;

    /// @notice Supplies `assets` or `shares` on behalf of `onBehalf`, optionally calling back the caller's
    /// `onMorphoSupply` function with the given `data`.
    /// @dev Either `assets` or `shares` should be zero. Most usecases should rely on `assets` as an input so the caller
    /// is guaranteed to have `assets` tokens pulled from their balance, but the possibility to mint a specific amount
    /// of shares is given for full compatibility and precision.
    /// @dev If the supply of a market gets depleted, the supply share price instantly resets to
    /// `VIRTUAL_ASSETS`:`VIRTUAL_SHARES`.
    /// @dev Supplying a large amount can revert for overflow.
    /// @param marketParams The market to supply assets to.
    /// @param assets The amount of assets to supply.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address that will own the increased supply position.
    /// @param data Arbitrary data to pass to the `onMorphoSupply` callback. Pass empty data if not needed.
    /// @return assetsSupplied The amount of assets supplied.
    /// @return sharesSupplied The amount of shares minted.
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);

    /// @notice Withdraws `assets` or `shares` on behalf of `onBehalf` to `receiver`.
    /// @dev Either `assets` or `shares` should be zero. To withdraw max, pass the `shares`'s balance of `onBehalf`.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Withdrawing an amount corresponding to more shares than supplied will revert for underflow.
    /// @dev It is advised to use the `shares` input when withdrawing the full position to avoid reverts due to
    /// conversion roundings between shares and assets.
    /// @param marketParams The market to withdraw assets from.
    /// @param assets The amount of assets to withdraw.
    /// @param shares The amount of shares to burn.
    /// @param onBehalf The address of the owner of the supply position.
    /// @param receiver The address that will receive the withdrawn assets.
    /// @return assetsWithdrawn The amount of assets withdrawn.
    /// @return sharesWithdrawn The amount of shares burned.
    function withdraw(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsWithdrawn, uint256 sharesWithdrawn);

    /// @notice Borrows `assets` or `shares` on behalf of `onBehalf` to `receiver`.
    /// @dev Either `assets` or `shares` should be zero. Most usecases should rely on `assets` as an input so the caller
    /// is guaranteed to borrow `assets` of tokens, but the possibility to mint a specific amount of shares is given for
    /// full compatibility and precision.
    /// @dev If the borrow of a market gets depleted, the borrow share price instantly resets to
    /// `VIRTUAL_ASSETS`:`VIRTUAL_SHARES`.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Borrowing a large amount can revert for overflow.
    /// @param marketParams The market to borrow assets from.
    /// @param assets The amount of assets to borrow.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address that will own the increased borrow position.
    /// @param receiver The address that will receive the borrowed assets.
    /// @return assetsBorrowed The amount of assets borrowed.
    /// @return sharesBorrowed The amount of shares minted.
    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    /// @notice Repays `assets` or `shares` on behalf of `onBehalf`, optionally calling back the caller's
    /// `onMorphoReplay` function with the given `data`.
    /// @dev Either `assets` or `shares` should be zero. To repay max, pass the `shares`'s balance of `onBehalf`.
    /// @dev Repaying an amount corresponding to more shares than borrowed will revert for underflow.
    /// @dev It is advised to use the `shares` input when repaying the full position to avoid reverts due to conversion
    /// roundings between shares and assets.
    /// @param marketParams The market to repay assets to.
    /// @param assets The amount of assets to repay.
    /// @param shares The amount of shares to burn.
    /// @param onBehalf The address of the owner of the debt position.
    /// @param data Arbitrary data to pass to the `onMorphoRepay` callback. Pass empty data if not needed.
    /// @return assetsRepaid The amount of assets repaid.
    /// @return sharesRepaid The amount of shares burned.
    function repay(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsRepaid, uint256 sharesRepaid);

    /// @notice Supplies `assets` of collateral on behalf of `onBehalf`, optionally calling back the caller's
    /// `onMorphoSupplyCollateral` function with the given `data`.
    /// @dev Interest are not accrued since it's not required and it saves gas.
    /// @dev Supplying a large amount can revert for overflow.
    /// @param marketParams The market to supply collateral to.
    /// @param assets The amount of collateral to supply.
    /// @param onBehalf The address that will own the increased collateral position.
    /// @param data Arbitrary data to pass to the `onMorphoSupplyCollateral` callback. Pass empty data if not needed.
    function supplyCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf, bytes memory data)
        external;

    /// @notice Withdraws `assets` of collateral on behalf of `onBehalf` to `receiver`.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Withdrawing an amount corresponding to more collateral than supplied will revert for underflow.
    /// @param marketParams The market to withdraw collateral from.
    /// @param assets The amount of collateral to withdraw.
    /// @param onBehalf The address of the owner of the collateral position.
    /// @param receiver The address that will receive the collateral assets.
    function withdrawCollateral(MarketParams memory marketParams, uint256 assets, address onBehalf, address receiver)
        external;

    /// @notice Liquidates the given `repaidShares` of debt asset or seize the given `seizedAssets` of collateral on the
    /// given market `marketParams` of the given `borrower`'s position, optionally calling back the caller's
    /// `onMorphoLiquidate` function with the given `data`.
    /// @dev Either `seizedAssets` or `repaidShares` should be zero.
    /// @dev Seizing more than the collateral balance will underflow and revert without any error message.
    /// @dev Repaying more than the borrow balance will underflow and revert without any error message.
    /// @param marketParams The market of the position.
    /// @param borrower The owner of the position.
    /// @param seizedAssets The amount of collateral to seize.
    /// @param repaidShares The amount of shares to repay.
    /// @param data Arbitrary data to pass to the `onMorphoLiquidate` callback. Pass empty data if not needed.
    /// @return The amount of assets seized.
    /// @return The amount of assets repaid.
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes memory data
    ) external returns (uint256, uint256);

    /// @notice Executes a flash loan.
    /// @dev Flash loans have access to the whole balance of the contract (the liquidity and deposited collateral of all
    /// markets combined, plus donations).
    /// @dev Warning: Not ERC-3156 compliant but compatibility is easily reached:
    /// - `flashFee` is zero.
    /// - `maxFlashLoan` is the token's balance of this contract.
    /// - The receiver of `assets` is the caller.
    /// @param token The token to flash loan.
    /// @param assets The amount of assets to flash loan.
    /// @param data Arbitrary data to pass to the `onMorphoFlashLoan` callback.
    function flashLoan(address token, uint256 assets, bytes calldata data) external;

    /// @notice Sets the authorization for `authorized` to manage `msg.sender`'s positions.
    /// @param authorized The authorized address.
    /// @param newIsAuthorized The new authorization status.
    function setAuthorization(address authorized, bool newIsAuthorized) external;

    /// @notice Sets the authorization for `authorization.authorized` to manage `authorization.authorizer`'s positions.
    /// @dev Warning: Reverts if the signature has already been submitted.
    /// @dev The signature is malleable, but it has no impact on the security here.
    /// @dev The nonce is passed as argument to be able to revert with a different error message.
    /// @param authorization The `Authorization` struct.
    /// @param signature The signature.
    function setAuthorizationWithSig(Authorization calldata authorization, Signature calldata signature) external;

    /// @notice Accrues interest for the given market `marketParams`.
    function accrueInterest(MarketParams memory marketParams) external;

    /// @notice Returns the data stored on the different `slots`.
    function extSloads(bytes32[] memory slots) external view returns (bytes32[] memory);
}

/// @dev This interface is inherited by Morpho so that function signatures are checked by the compiler.
/// @dev Consider using the IMorpho interface instead of this one.
interface IMorphoStaticTyping is IMorphoBase {
    /// @notice The state of the position of `user` on the market corresponding to `id`.
    /// @dev Warning: For `feeRecipient`, `supplyShares` does not contain the accrued shares since the last interest
    /// accrual.
    function position(Id id, address user)
        external
        view
        returns (uint256 supplyShares, uint128 borrowShares, uint128 collateral);

    /// @notice The state of the market corresponding to `id`.
    /// @dev Warning: `totalSupplyAssets` does not contain the accrued interest since the last interest accrual.
    /// @dev Warning: `totalBorrowAssets` does not contain the accrued interest since the last interest accrual.
    /// @dev Warning: `totalSupplyShares` does not contain the accrued shares by `feeRecipient` since the last interest
    /// accrual.
    function market(Id id)
        external
        view
        returns (
            uint128 totalSupplyAssets,
            uint128 totalSupplyShares,
            uint128 totalBorrowAssets,
            uint128 totalBorrowShares,
            uint128 lastUpdate,
            uint128 fee
        );

    /// @notice The market params corresponding to `id`.
    /// @dev This mapping is not used in Morpho. It is there to enable reducing the cost associated to calldata on layer
    /// 2s by creating a wrapper contract with functions that take `id` as input instead of `marketParams`.
    function idToMarketParams(Id id)
        external
        view
        returns (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv);
}

/// @title IMorpho
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @dev Use this interface for Morpho to have access to all the functions with the appropriate function signatures.
interface IMorpho is IMorphoBase {
    /// @notice The state of the position of `user` on the market corresponding to `id`.
    /// @dev Warning: For `feeRecipient`, `p.supplyShares` does not contain the accrued shares since the last interest
    /// accrual.
    function position(Id id, address user) external view returns (Position memory p);

    /// @notice The state of the market corresponding to `id`.
    /// @dev Warning: `m.totalSupplyAssets` does not contain the accrued interest since the last interest accrual.
    /// @dev Warning: `m.totalBorrowAssets` does not contain the accrued interest since the last interest accrual.
    /// @dev Warning: `m.totalSupplyShares` does not contain the accrued shares by `feeRecipient` since the last
    /// interest accrual.
    function market(Id id) external view returns (Market memory m);

    /// @notice The market params corresponding to `id`.
    /// @dev This mapping is not used in Morpho. It is there to enable reducing the cost associated to calldata on layer
    /// 2s by creating a wrapper contract with functions that take `id` as input instead of `marketParams`.
    function idToMarketParams(Id id) external view returns (MarketParams memory);
}

// OpenZeppelin Contracts (last updated v5.0.0) (interfaces/IERC4626.sol)

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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

    /**
     * @dev Returns the value of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the value of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves a `value` amount of tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets a `value` amount of tokens as the allowance of `spender` over the
     * caller's tokens.
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
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Moves a `value` amount of tokens from `from` to `to` using the
     * allowance mechanism. `value` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Metadata.sol)

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

/**
 * @dev Interface of the ERC4626 "Tokenized Vault Standard", as defined in
 * https://eips.ethereum.org/EIPS/eip-4626[ERC-4626].
 */
interface IERC4626 is IERC20, IERC20Metadata {
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    /**
     * @dev Returns the address of the underlying token used for the Vault for accounting, depositing, and withdrawing.
     *
     * - MUST be an ERC-20 token contract.
     * - MUST NOT revert.
     */
    function asset() external view returns (address assetTokenAddress);

    /**
     * @dev Returns the total amount of the underlying asset that is “managed” by Vault.
     *
     * - SHOULD include any compounding that occurs from yield.
     * - MUST be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT revert.
     */
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /**
     * @dev Returns the amount of shares that the Vault would exchange for the amount of assets provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Returns the amount of assets that the Vault would exchange for the amount of shares provided, in an ideal
     * scenario where all the conditions are met.
     *
     * - MUST NOT be inclusive of any fees that are charged against assets in the Vault.
     * - MUST NOT show any variations depending on the caller.
     * - MUST NOT reflect slippage or other on-chain conditions, when performing the actual exchange.
     * - MUST NOT revert.
     *
     * NOTE: This calculation MAY NOT reflect the “per-user” price-per-share, and instead should reflect the
     * “average-user’s” price-per-share, meaning what the average user should expect to see when exchanging to and
     * from.
     */
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Returns the maximum amount of the underlying asset that can be deposited into the Vault for the receiver,
     * through a deposit call.
     *
     * - MUST return a limited value if receiver is subject to some deposit limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of assets that may be deposited.
     * - MUST NOT revert.
     */
    function maxDeposit(address receiver) external view returns (uint256 maxAssets);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their deposit at the current block, given
     * current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of Vault shares that would be minted in a deposit
     *   call in the same transaction. I.e. deposit should return the same or more shares as previewDeposit if called
     *   in the same transaction.
     * - MUST NOT account for deposit limits like those returned from maxDeposit and should always act as though the
     *   deposit would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewDeposit SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Mints shares Vault shares to receiver by depositing exactly amount of underlying tokens.
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   deposit execution, and are accounted for during deposit.
     * - MUST revert if all of assets cannot be deposited (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /**
     * @dev Returns the maximum amount of the Vault shares that can be minted for the receiver, through a mint call.
     * - MUST return a limited value if receiver is subject to some mint limit.
     * - MUST return 2 ** 256 - 1 if there is no limit on the maximum amount of shares that may be minted.
     * - MUST NOT revert.
     */
    function maxMint(address receiver) external view returns (uint256 maxShares);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their mint at the current block, given
     * current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of assets that would be deposited in a mint call
     *   in the same transaction. I.e. mint should return the same or fewer assets as previewMint if called in the
     *   same transaction.
     * - MUST NOT account for mint limits like those returned from maxMint and should always act as though the mint
     *   would be accepted, regardless if the user has enough tokens approved, etc.
     * - MUST be inclusive of deposit fees. Integrators should be aware of the existence of deposit fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewMint SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by minting.
     */
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Mints exactly shares Vault shares to receiver by depositing amount of underlying tokens.
     *
     * - MUST emit the Deposit event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the mint
     *   execution, and are accounted for during mint.
     * - MUST revert if all of shares cannot be minted (due to deposit limit being reached, slippage, the user not
     *   approving enough underlying tokens to the Vault contract, etc).
     *
     * NOTE: most implementations will require pre-approval of the Vault with the Vault’s underlying asset token.
     */
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /**
     * @dev Returns the maximum amount of the underlying asset that can be withdrawn from the owner balance in the
     * Vault, through a withdraw call.
     *
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their withdrawal at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no fewer than the exact amount of Vault shares that would be burned in a withdraw
     *   call in the same transaction. I.e. withdraw should return the same or fewer shares as previewWithdraw if
     *   called
     *   in the same transaction.
     * - MUST NOT account for withdrawal limits like those returned from maxWithdraw and should always act as though
     *   the withdrawal would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToShares and previewWithdraw SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by depositing.
     */
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /**
     * @dev Burns shares from owner and sends exactly assets of underlying tokens to receiver.
     *
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   withdraw execution, and are accounted for during withdraw.
     * - MUST revert if all of assets cannot be withdrawn (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * Note that some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /**
     * @dev Returns the maximum amount of Vault shares that can be redeemed from the owner balance in the Vault,
     * through a redeem call.
     *
     * - MUST return a limited value if owner is subject to some withdrawal limit or timelock.
     * - MUST return balanceOf(owner) if owner is not subject to any withdrawal limit or timelock.
     * - MUST NOT revert.
     */
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    /**
     * @dev Allows an on-chain or off-chain user to simulate the effects of their redeemption at the current block,
     * given current on-chain conditions.
     *
     * - MUST return as close to and no more than the exact amount of assets that would be withdrawn in a redeem call
     *   in the same transaction. I.e. redeem should return the same or more assets as previewRedeem if called in the
     *   same transaction.
     * - MUST NOT account for redemption limits like those returned from maxRedeem and should always act as though the
     *   redemption would be accepted, regardless if the user has enough shares, etc.
     * - MUST be inclusive of withdrawal fees. Integrators should be aware of the existence of withdrawal fees.
     * - MUST NOT revert.
     *
     * NOTE: any unfavorable discrepancy between convertToAssets and previewRedeem SHOULD be considered slippage in
     * share price or some other type of condition, meaning the depositor will lose assets by redeeming.
     */
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /**
     * @dev Burns exactly shares from owner and sends assets of underlying tokens to receiver.
     *
     * - MUST emit the Withdraw event.
     * - MAY support an additional flow in which the underlying tokens are owned by the Vault contract before the
     *   redeem execution, and are accounted for during redeem.
     * - MUST revert if all of shares cannot be redeemed (due to withdrawal limit being reached, slippage, the owner
     *   not having enough shares, etc).
     *
     * NOTE: some implementations will require pre-requesting to the Vault before a withdrawal may be performed.
     * Those methods should be performed separately.
     */
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}

// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/extensions/IERC20Permit.sol)

/**
 * @dev Interface of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on {IERC20-approve}, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * ==== Security Considerations
 *
 * There are two important considerations concerning the use of `permit`. The first is that a valid permit signature
 * expresses an allowance, and it should not be assumed to convey additional meaning. In particular, it should not be
 * considered as an intention to spend the allowance in any specific way. The second is that because permits have
 * built-in replay protection and can be submitted by anyone, they can be frontrun. A protocol that uses permits should
 * take this into consideration and allow a `permit` call to fail. Combining these two aspects, a pattern that may be
 * generally recommended is:
 *
 * ```solidity
 * function doThingWithPermit(..., uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
 *     try token.permit(msg.sender, address(this), value, deadline, v, r, s) {} catch {}
 *     doThing(..., value);
 * }
 *
 * function doThing(..., uint256 value) public {
 *     token.safeTransferFrom(msg.sender, address(this), value);
 *     ...
 * }
 * ```
 *
 * Observe that: 1) `msg.sender` is used as the owner, leaving no ambiguity as to the signer intent, and 2) the use of
 * `try/catch` allows the permit to fail and makes the code tolerant to frontrunning. (See also
 * {SafeERC20-safeTransferFrom}).
 *
 * Additionally, note that smart contract wallets (such as Argent or Safe) are not able to produce permit signatures, so
 * contracts should have entry points that don't rely on permit.
 */
interface IERC20Permit {
    /**
     * @dev Sets `value` as the allowance of `spender` over ``owner``'s tokens,
     * given ``owner``'s signed approval.
     *
     * IMPORTANT: The same issues {IERC20-approve} has related to transaction
     * ordering also apply here.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `deadline` must be a timestamp in the future.
     * - `v`, `r` and `s` must be a valid `secp256k1` signature from `owner`
     * over the EIP712-formatted function arguments.
     * - the signature must use ``owner``'s current nonce (see {nonces}).
     *
     * For more information on the signature format, see the
     * https://eips.ethereum.org/EIPS/eip-2612#specification[relevant EIP
     * section].
     *
     * CAUTION: See Security Considerations above.
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Returns the current nonce for `owner`. This value must be
     * included whenever a signature is generated for {permit}.
     *
     * Every successful call to {permit} increases ``owner``'s nonce by one. This
     * prevents a signature from being used multiple times.
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Returns the domain separator used in the encoding of the signature for {permit}, as defined by {EIP712}.
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}

struct MarketConfig {
    /// @notice The maximum amount of assets that can be allocated to the market.
    uint184 cap;
    /// @notice Whether the market is in the withdraw queue.
    bool enabled;
    /// @notice The timestamp at which the market can be instantly removed from the withdraw queue.
    uint64 removableAt;
}

struct PendingUint192 {
    /// @notice The pending value to set.
    uint192 value;
    /// @notice The timestamp at which the pending value becomes valid.
    uint64 validAt;
}

struct PendingAddress {
    /// @notice The pending value to set.
    address value;
    /// @notice The timestamp at which the pending value becomes valid.
    uint64 validAt;
}

/// @title PendingLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to manage pending values and their validity timestamp.
library PendingLib {
    /// @dev Updates `pending`'s value to `newValue` and its corresponding `validAt` timestamp.
    /// @dev Assumes `timelock` <= `MAX_TIMELOCK`.
    function update(PendingUint192 storage pending, uint184 newValue, uint256 timelock) internal {
        pending.value = newValue;
        // Safe "unchecked" cast because timelock <= MAX_TIMELOCK.
        pending.validAt = uint64(block.timestamp + timelock);
    }

    /// @dev Updates `pending`'s value to `newValue` and its corresponding `validAt` timestamp.
    /// @dev Assumes `timelock` <= `MAX_TIMELOCK`.
    function update(PendingAddress storage pending, address newValue, uint256 timelock) internal {
        pending.value = newValue;
        // Safe "unchecked" cast because timelock <= MAX_TIMELOCK.
        pending.validAt = uint64(block.timestamp + timelock);
    }
}

/// @dev Either `assets` or `shares` should be zero.
struct MarketAllocation {
    /// @notice The market to allocate.
    MarketParams marketParams;
    /// @notice The amount of assets to allocate.
    uint256 assets;
}

interface IMulticall {
    function multicall(bytes[] calldata) external returns (bytes[] memory);
}

interface IOwnable {
    function owner() external returns (address);
    function transferOwnership(address) external;
    function renounceOwnership() external;
    function acceptOwnership() external;
    function pendingOwner() external view returns (address);
}

/// @dev This interface is used for factorizing IMetaMorphoStaticTyping and IMetaMorpho.
/// @dev Consider using the IMetaMorpho interface instead of this one.
interface IMetaMorphoBase {
    /// @notice The address of the Morpho contract.
    function MORPHO() external view returns (IMorpho);

    /// @notice The address of the curator.
    function curator() external view returns (address);

    /// @notice Stores whether an address is an allocator or not.
    function isAllocator(address target) external view returns (bool);

    /// @notice The current guardian. Can be set even without the timelock set.
    function guardian() external view returns (address);

    /// @notice The current fee.
    function fee() external view returns (uint96);

    /// @notice The fee recipient.
    function feeRecipient() external view returns (address);

    /// @notice The skim recipient.
    function skimRecipient() external view returns (address);

    /// @notice The current timelock.
    function timelock() external view returns (uint256);

    /// @dev Stores the order of markets on which liquidity is supplied upon deposit.
    /// @dev Can contain any market. A market is skipped as soon as its supply cap is reached.
    function supplyQueue(uint256) external view returns (Id);

    /// @notice Returns the length of the supply queue.
    function supplyQueueLength() external view returns (uint256);

    /// @dev Stores the order of markets from which liquidity is withdrawn upon withdrawal.
    /// @dev Always contain all non-zero cap markets as well as all markets on which the vault supplies liquidity,
    /// without duplicate.
    function withdrawQueue(uint256) external view returns (Id);

    /// @notice Returns the length of the withdraw queue.
    function withdrawQueueLength() external view returns (uint256);

    /// @notice Stores the total assets managed by this vault when the fee was last accrued.
    /// @dev May be a little off `totalAssets()` after each interaction, due to some roundings.
    function lastTotalAssets() external view returns (uint256);

    /// @notice Submits a `newTimelock`.
    /// @dev In case the new timelock is higher than the current one, the timelock is set immediately.
    /// @dev Warning: Submitting a timelock will overwrite the current pending timelock.
    function submitTimelock(uint256 newTimelock) external;

    /// @notice Accepts the pending timelock.
    function acceptTimelock() external;

    /// @notice Revokes the pending timelock.
    function revokePendingTimelock() external;

    /// @notice Submits a `newSupplyCap` for the market defined by `marketParams`.
    /// @dev In case the new cap is lower than the current one, the cap is set immediately.
    /// @dev Warning: Submitting a cap will overwrite the current pending cap.
    function submitCap(MarketParams memory marketParams, uint256 newSupplyCap) external;

    /// @notice Accepts the pending cap of the market defined by `id`.
    function acceptCap(Id id) external;

    /// @notice Revokes the pending cap of the market defined by `id`.
    function revokePendingCap(Id id) external;

    /// @notice Submits a forced market removal from the vault, potentially losing all funds supplied to the market.
    /// @dev Warning: Submitting a forced removal will overwrite the timestamp at which the market will be removable.
    function submitMarketRemoval(Id id) external;

    /// @notice Revokes the pending removal of the market defined by `id`.
    function revokePendingMarketRemoval(Id id) external;

    /// @notice Submits a `newGuardian`.
    /// @notice Warning: a malicious guardian could disrupt the vault's operation, and would have the power to revoke
    /// any pending guardian.
    /// @dev In case there is no guardian, the gardian is set immediately.
    /// @dev Warning: Submitting a gardian will overwrite the current pending gardian.
    function submitGuardian(address newGuardian) external;

    /// @notice Accepts the pending guardian.
    function acceptGuardian() external;

    /// @notice Revokes the pending guardian.
    function revokePendingGuardian() external;

    /// @notice Skims the vault `token` balance to `skimRecipient`.
    function skim(address) external;

    /// @notice Sets `newAllocator` as an allocator or not (`newIsAllocator`).
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    /// @notice Sets `curator` to `newCurator`.
    function setCurator(address newCurator) external;

    /// @notice Sets the `fee` to `newFee`.
    function setFee(uint256 newFee) external;

    /// @notice Sets `feeRecipient` to `newFeeRecipient`.
    function setFeeRecipient(address newFeeRecipient) external;

    /// @notice Sets `skimRecipient` to `newSkimRecipient`.
    function setSkimRecipient(address newSkimRecipient) external;

    /// @notice Sets `supplyQueue` to `newSupplyQueue`.
    /// @param newSupplyQueue is an array of enabled markets, and can contain duplicate markets, but it would only
    /// increase the cost of depositing to the vault.
    function setSupplyQueue(Id[] calldata newSupplyQueue) external;

    /// @notice Sets the withdraw queue as a permutation of the previous one, although markets with both zero cap and
    /// zero vault's supply can be removed from the permutation.
    /// @notice This is the only entry point to disable a market.
    /// @notice Removing a market requires the vault to have 0 supply on it; but anyone can supply on behalf of the
    /// vault so the call to `updateWithdrawQueue` can be griefed by a frontrun. To circumvent this, the allocator can
    /// simply bundle a reallocation that withdraws max from this market with a call to `updateWithdrawQueue`.
    /// @param indexes The indexes of each market in the previous withdraw queue, in the new withdraw queue's order.
    function updateWithdrawQueue(uint256[] calldata indexes) external;

    /// @notice Reallocates the vault's liquidity so as to reach a given allocation of assets on each given market.
    /// @notice The allocator can withdraw from any market, even if it's not in the withdraw queue, as long as the loan
    /// token of the market is the same as the vault's asset.
    /// @dev The behavior of the reallocation can be altered by state changes, including:
    /// - Deposits on the vault that supplies to markets that are expected to be supplied to during reallocation.
    /// - Withdrawals from the vault that withdraws from markets that are expected to be withdrawn from during
    /// reallocation.
    /// - Donations to the vault on markets that are expected to be supplied to during reallocation.
    /// - Withdrawals from markets that are expected to be withdrawn from during reallocation.
    function reallocate(MarketAllocation[] calldata allocations) external;
}

/// @dev This interface is inherited by MetaMorpho so that function signatures are checked by the compiler.
/// @dev Consider using the IMetaMorpho interface instead of this one.
interface IMetaMorphoStaticTyping is IMetaMorphoBase {
    /// @notice Returns the current configuration of each market.
    function config(Id) external view returns (uint184 cap, bool enabled, uint64 removableAt);

    /// @notice Returns the pending guardian.
    function pendingGuardian() external view returns (address guardian, uint64 validAt);

    /// @notice Returns the pending cap for each market.
    function pendingCap(Id) external view returns (uint192 value, uint64 validAt);

    /// @notice Returns the pending timelock.
    function pendingTimelock() external view returns (uint192 value, uint64 validAt);
}

/// @title IMetaMorpho
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @dev Use this interface for MetaMorpho to have access to all the functions with the appropriate function signatures.
interface IMetaMorpho is IMetaMorphoBase, IERC4626, IERC20Permit, IOwnable, IMulticall {
    /// @notice Returns the current configuration of each market.
    function config(Id) external view returns (MarketConfig memory);

    /// @notice Returns the pending guardian.
    function pendingGuardian() external view returns (PendingAddress memory);

    /// @notice Returns the pending cap for each market.
    function pendingCap(Id) external view returns (PendingUint192 memory);

    /// @notice Returns the pending timelock.
    function pendingTimelock() external view returns (PendingUint192 memory);
}

/// @title MarketParamsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to convert a market to its id.
library MarketParamsLib {
    /// @notice The length of the data used to compute the id of a market.
    /// @dev The length is 5 * 32 because `MarketParams` has 5 variables of 32 bytes each.
    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    /// @notice Returns the id of the market `marketParams`.
    function id(MarketParams memory marketParams) internal pure returns (Id marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(marketParams, MARKET_PARAMS_BYTES_LENGTH)
        }
    }
}

uint256 constant WAD = 1e18;

/// @title MathLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to manage fixed-point arithmetic.
library MathLib {
    /// @dev Returns (`x` * `y`) / `WAD` rounded down.
    function wMulDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, y, WAD);
    }

    /// @dev Returns (`x` * `WAD`) / `y` rounded down.
    function wDivDown(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivDown(x, WAD, y);
    }

    /// @dev Returns (`x` * `WAD`) / `y` rounded up.
    function wDivUp(uint256 x, uint256 y) internal pure returns (uint256) {
        return mulDivUp(x, WAD, y);
    }

    /// @dev Returns (`x` * `y`) / `d` rounded down.
    function mulDivDown(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y) / d;
    }

    /// @dev Returns (`x` * `y`) / `d` rounded up.
    function mulDivUp(uint256 x, uint256 y, uint256 d) internal pure returns (uint256) {
        return (x * y + (d - 1)) / d;
    }

    /// @dev Returns the sum of the first three non-zero terms of a Taylor expansion of e^(nx) - 1, to approximate a
    /// continuous compound interest rate.
    function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
        uint256 firstTerm = x * n;
        uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
        uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);

        return firstTerm + secondTerm + thirdTerm;
    }
}

/// @title SharesMathLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Shares management library.
/// @dev This implementation mitigates share price manipulations, using OpenZeppelin's method of virtual shares:
/// https://docs.openzeppelin.com/contracts/4.x/erc4626#inflation-attack.
library SharesMathLib {
    using MathLib for uint256;

    /// @dev The number of virtual shares has been chosen low enough to prevent overflows, and high enough to ensure
    /// high precision computations.
    uint256 internal constant VIRTUAL_SHARES = 1e6;

    /// @dev A number of virtual assets of 1 enforces a conversion rate between shares and assets when a market is
    /// empty.
    uint256 internal constant VIRTUAL_ASSETS = 1;

    /// @dev Calculates the value of `assets` quoted in shares, rounding down.
    function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivDown(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of `shares` quoted in assets, rounding down.
    function toAssetsDown(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivDown(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }

    /// @dev Calculates the value of `assets` quoted in shares, rounding up.
    function toSharesUp(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return assets.mulDivUp(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
    }

    /// @dev Calculates the value of `shares` quoted in assets, rounding up.
    function toAssetsUp(uint256 shares, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
        return shares.mulDivUp(totalAssets + VIRTUAL_ASSETS, totalShares + VIRTUAL_SHARES);
    }
}

/// @title IIrm
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface that Interest Rate Models (IRMs) used by Morpho must implement.
interface IIrm {
    /// @notice Returns the borrow rate of the market `marketParams`.
    /// @dev Assumes that `market` corresponds to `marketParams`.
    function borrowRate(MarketParams memory marketParams, Market memory market) external returns (uint256);

    /// @notice Returns the borrow rate of the market `marketParams` without modifying any storage.
    /// @dev Assumes that `market` corresponds to `marketParams`.
    function borrowRateView(MarketParams memory marketParams, Market memory market) external view returns (uint256);
}

/// @title ErrorsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing error messages.
library ErrorsLib {
    /// @notice Thrown when the caller is not the owner.
    string internal constant NOT_OWNER = "not owner";

    /// @notice Thrown when the LLTV to enable exceeds the maximum LLTV.
    string internal constant MAX_LLTV_EXCEEDED = "max LLTV exceeded";

    /// @notice Thrown when the fee to set exceeds the maximum fee.
    string internal constant MAX_FEE_EXCEEDED = "max fee exceeded";

    /// @notice Thrown when the value is already set.
    string internal constant ALREADY_SET = "already set";

    /// @notice Thrown when the IRM is not enabled at market creation.
    string internal constant IRM_NOT_ENABLED = "IRM not enabled";

    /// @notice Thrown when the LLTV is not enabled at market creation.
    string internal constant LLTV_NOT_ENABLED = "LLTV not enabled";

    /// @notice Thrown when the market is already created.
    string internal constant MARKET_ALREADY_CREATED = "market already created";

    /// @notice Thrown when the market is not created.
    string internal constant MARKET_NOT_CREATED = "market not created";

    /// @notice Thrown when not exactly one of the input amount is zero.
    string internal constant INCONSISTENT_INPUT = "inconsistent input";

    /// @notice Thrown when zero assets is passed as input.
    string internal constant ZERO_ASSETS = "zero assets";

    /// @notice Thrown when a zero address is passed as input.
    string internal constant ZERO_ADDRESS = "zero address";

    /// @notice Thrown when the caller is not authorized to conduct an action.
    string internal constant UNAUTHORIZED = "unauthorized";

    /// @notice Thrown when the collateral is insufficient to `borrow` or `withdrawCollateral`.
    string internal constant INSUFFICIENT_COLLATERAL = "insufficient collateral";

    /// @notice Thrown when the liquidity is insufficient to `withdraw` or `borrow`.
    string internal constant INSUFFICIENT_LIQUIDITY = "insufficient liquidity";

    /// @notice Thrown when the position to liquidate is healthy.
    string internal constant HEALTHY_POSITION = "position is healthy";

    /// @notice Thrown when the authorization signature is invalid.
    string internal constant INVALID_SIGNATURE = "invalid signature";

    /// @notice Thrown when the authorization signature is expired.
    string internal constant SIGNATURE_EXPIRED = "signature expired";

    /// @notice Thrown when the nonce is invalid.
    string internal constant INVALID_NONCE = "invalid nonce";

    /// @notice Thrown when a token transfer reverted.
    string internal constant TRANSFER_REVERTED = "transfer reverted";

    /// @notice Thrown when a token transfer returned false.
    string internal constant TRANSFER_RETURNED_FALSE = "transfer returned false";

    /// @notice Thrown when a token transferFrom reverted.
    string internal constant TRANSFER_FROM_REVERTED = "transferFrom reverted";

    /// @notice Thrown when a token transferFrom returned false
    string internal constant TRANSFER_FROM_RETURNED_FALSE = "transferFrom returned false";

    /// @notice Thrown when the maximum uint128 is exceeded.
    string internal constant MAX_UINT128_EXCEEDED = "max uint128 exceeded";
}

/// @title UtilsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library exposing helpers.
/// @dev Inspired by https://github.com/morpho-org/morpho-utils.
library UtilsLib {
    /// @dev Returns true if there is exactly one zero among `x` and `y`.
    function exactlyOneZero(uint256 x, uint256 y) internal pure returns (bool z) {
        assembly {
            z := xor(iszero(x), iszero(y))
        }
    }

    /// @dev Returns the min of `x` and `y`.
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := xor(x, mul(xor(x, y), lt(y, x)))
        }
    }

    /// @dev Returns `x` safely cast to uint128.
    function toUint128(uint256 x) internal pure returns (uint128) {
        require(x <= type(uint128).max, ErrorsLib.MAX_UINT128_EXCEEDED);
        return uint128(x);
    }

    /// @dev Returns max(x - y, 0).
    function zeroFloorSub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(gt(x, y), sub(x, y))
        }
    }
}

/// @title MorphoStorageLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Helper library exposing getters to access Morpho storage variables' slot.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
library MorphoStorageLib {
    /* SLOTS */

    uint256 internal constant OWNER_SLOT = 0;
    uint256 internal constant FEE_RECIPIENT_SLOT = 1;
    uint256 internal constant POSITION_SLOT = 2;
    uint256 internal constant MARKET_SLOT = 3;
    uint256 internal constant IS_IRM_ENABLED_SLOT = 4;
    uint256 internal constant IS_LLTV_ENABLED_SLOT = 5;
    uint256 internal constant IS_AUTHORIZED_SLOT = 6;
    uint256 internal constant NONCE_SLOT = 7;
    uint256 internal constant ID_TO_MARKET_PARAMS_SLOT = 8;

    /* SLOT OFFSETS */

    uint256 internal constant LOAN_TOKEN_OFFSET = 0;
    uint256 internal constant COLLATERAL_TOKEN_OFFSET = 1;
    uint256 internal constant ORACLE_OFFSET = 2;
    uint256 internal constant IRM_OFFSET = 3;
    uint256 internal constant LLTV_OFFSET = 4;

    uint256 internal constant SUPPLY_SHARES_OFFSET = 0;
    uint256 internal constant BORROW_SHARES_AND_COLLATERAL_OFFSET = 1;

    uint256 internal constant TOTAL_SUPPLY_ASSETS_AND_SHARES_OFFSET = 0;
    uint256 internal constant TOTAL_BORROW_ASSETS_AND_SHARES_OFFSET = 1;
    uint256 internal constant LAST_UPDATE_AND_FEE_OFFSET = 2;

    /* GETTERS */

    function ownerSlot() internal pure returns (bytes32) {
        return bytes32(OWNER_SLOT);
    }

    function feeRecipientSlot() internal pure returns (bytes32) {
        return bytes32(FEE_RECIPIENT_SLOT);
    }

    function positionSupplySharesSlot(Id id, address user) internal pure returns (bytes32) {
        return bytes32(
            uint256(keccak256(abi.encode(user, keccak256(abi.encode(id, POSITION_SLOT))))) + SUPPLY_SHARES_OFFSET
        );
    }

    function positionBorrowSharesAndCollateralSlot(Id id, address user) internal pure returns (bytes32) {
        return bytes32(
            uint256(keccak256(abi.encode(user, keccak256(abi.encode(id, POSITION_SLOT)))))
                + BORROW_SHARES_AND_COLLATERAL_OFFSET
        );
    }

    function marketTotalSupplyAssetsAndSharesSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, MARKET_SLOT))) + TOTAL_SUPPLY_ASSETS_AND_SHARES_OFFSET);
    }

    function marketTotalBorrowAssetsAndSharesSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, MARKET_SLOT))) + TOTAL_BORROW_ASSETS_AND_SHARES_OFFSET);
    }

    function marketLastUpdateAndFeeSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, MARKET_SLOT))) + LAST_UPDATE_AND_FEE_OFFSET);
    }

    function isIrmEnabledSlot(address irm) internal pure returns (bytes32) {
        return keccak256(abi.encode(irm, IS_IRM_ENABLED_SLOT));
    }

    function isLltvEnabledSlot(uint256 lltv) internal pure returns (bytes32) {
        return keccak256(abi.encode(lltv, IS_LLTV_ENABLED_SLOT));
    }

    function isAuthorizedSlot(address authorizer, address authorizee) internal pure returns (bytes32) {
        return keccak256(abi.encode(authorizee, keccak256(abi.encode(authorizer, IS_AUTHORIZED_SLOT))));
    }

    function nonceSlot(address authorizer) internal pure returns (bytes32) {
        return keccak256(abi.encode(authorizer, NONCE_SLOT));
    }

    function idToLoanTokenSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_PARAMS_SLOT))) + LOAN_TOKEN_OFFSET);
    }

    function idToCollateralTokenSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_PARAMS_SLOT))) + COLLATERAL_TOKEN_OFFSET);
    }

    function idToOracleSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_PARAMS_SLOT))) + ORACLE_OFFSET);
    }

    function idToIrmSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_PARAMS_SLOT))) + IRM_OFFSET);
    }

    function idToLltvSlot(Id id) internal pure returns (bytes32) {
        return bytes32(uint256(keccak256(abi.encode(id, ID_TO_MARKET_PARAMS_SLOT))) + LLTV_OFFSET);
    }
}

/// @title MorphoLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Helper library to access Morpho storage variables.
/// @dev Warning: Supply and borrow getters may return outdated values that do not include accrued interest.
library MorphoLib {
    function supplyShares(IMorpho morpho, Id id, address user) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.positionSupplySharesSlot(id, user));
        return uint256(morpho.extSloads(slot)[0]);
    }

    function borrowShares(IMorpho morpho, Id id, address user) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.positionBorrowSharesAndCollateralSlot(id, user));
        return uint128(uint256(morpho.extSloads(slot)[0]));
    }

    function collateral(IMorpho morpho, Id id, address user) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.positionBorrowSharesAndCollateralSlot(id, user));
        return uint256(morpho.extSloads(slot)[0] >> 128);
    }

    function totalSupplyAssets(IMorpho morpho, Id id) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.marketTotalSupplyAssetsAndSharesSlot(id));
        return uint128(uint256(morpho.extSloads(slot)[0]));
    }

    function totalSupplyShares(IMorpho morpho, Id id) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.marketTotalSupplyAssetsAndSharesSlot(id));
        return uint256(morpho.extSloads(slot)[0] >> 128);
    }

    function totalBorrowAssets(IMorpho morpho, Id id) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.marketTotalBorrowAssetsAndSharesSlot(id));
        return uint128(uint256(morpho.extSloads(slot)[0]));
    }

    function totalBorrowShares(IMorpho morpho, Id id) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.marketTotalBorrowAssetsAndSharesSlot(id));
        return uint256(morpho.extSloads(slot)[0] >> 128);
    }

    function lastUpdate(IMorpho morpho, Id id) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.marketLastUpdateAndFeeSlot(id));
        return uint128(uint256(morpho.extSloads(slot)[0]));
    }

    function fee(IMorpho morpho, Id id) internal view returns (uint256) {
        bytes32[] memory slot = _array(MorphoStorageLib.marketLastUpdateAndFeeSlot(id));
        return uint256(morpho.extSloads(slot)[0] >> 128);
    }

    function _array(bytes32 x) private pure returns (bytes32[] memory) {
        bytes32[] memory res = new bytes32[](1);
        res[0] = x;
        return res;
    }
}

/// @title MorphoBalancesLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Helper library exposing getters with the expected value after interest accrual.
/// @dev This library is not used in Morpho itself and is intended to be used by integrators.
/// @dev The getter to retrieve the expected total borrow shares is not exposed because interest accrual does not apply
/// to it. The value can be queried directly on Morpho using `totalBorrowShares`.
library MorphoBalancesLib {
    using MathLib for uint256;
    using MathLib for uint128;
    using UtilsLib for uint256;
    using MorphoLib for IMorpho;
    using SharesMathLib for uint256;
    using MarketParamsLib for MarketParams;

    /// @notice Returns the expected market balances of a market after having accrued interest.
    /// @return The expected total supply assets.
    /// @return The expected total supply shares.
    /// @return The expected total borrow assets.
    /// @return The expected total borrow shares.
    function expectedMarketBalances(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256, uint256, uint256, uint256)
    {
        Id id = marketParams.id();

        Market memory market = morpho.market(id);

        uint256 elapsed = block.timestamp - market.lastUpdate;

        // Skipped if elapsed == 0 of if totalBorrowAssets == 0 because interest would be null.
        if (elapsed != 0 && market.totalBorrowAssets != 0) {
            uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market);
            uint256 interest = market.totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            market.totalBorrowAssets += interest.toUint128();
            market.totalSupplyAssets += interest.toUint128();

            if (market.fee != 0) {
                uint256 feeAmount = interest.wMulDown(market.fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                // that total supply is already updated.
                uint256 feeShares =
                    feeAmount.toSharesDown(market.totalSupplyAssets - feeAmount, market.totalSupplyShares);
                market.totalSupplyShares += feeShares.toUint128();
            }
        }

        return (market.totalSupplyAssets, market.totalSupplyShares, market.totalBorrowAssets, market.totalBorrowShares);
    }

    /// @notice Returns the expected total supply assets of a market after having accrued interest.
    function expectedTotalSupplyAssets(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupplyAssets)
    {
        (totalSupplyAssets,,,) = expectedMarketBalances(morpho, marketParams);
    }

    /// @notice Returns the expected total borrow assets of a market after having accrued interest.
    function expectedTotalBorrowAssets(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalBorrowAssets)
    {
        (,, totalBorrowAssets,) = expectedMarketBalances(morpho, marketParams);
    }

    /// @notice Returns the expected total supply shares of a market after having accrued interest.
    function expectedTotalSupplyShares(IMorpho morpho, MarketParams memory marketParams)
        internal
        view
        returns (uint256 totalSupplyShares)
    {
        (, totalSupplyShares,,) = expectedMarketBalances(morpho, marketParams);
    }

    /// @notice Returns the expected supply assets balance of `user` on a market after having accrued interest.
    /// @dev Warning: Wrong for `feeRecipient` because their supply shares increase is not taken into account.
    /// @dev Warning: Withdrawing a supply position using the expected assets balance can lead to a revert due to
    /// conversion roundings between shares and assets.
    function expectedSupplyAssets(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        Id id = marketParams.id();
        uint256 supplyShares = morpho.supplyShares(id, user);
        (uint256 totalSupplyAssets, uint256 totalSupplyShares,,) = expectedMarketBalances(morpho, marketParams);

        return supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    }

    /// @notice Returns the expected borrow assets balance of `user` on a market after having accrued interest.
    /// @dev Warning: repaying a borrow position using the expected assets balance can lead to a revert due to
    /// conversion roundings between shares and assets.
    function expectedBorrowAssets(IMorpho morpho, MarketParams memory marketParams, address user)
        internal
        view
        returns (uint256)
    {
        Id id = marketParams.id();
        uint256 borrowShares = morpho.borrowShares(id, user);
        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = expectedMarketBalances(morpho, marketParams);

        return borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
    }
}

interface IReallocationLogic {
  function setParams(
    TargetAllocator _targetAllocator,
    address _vaultAddress,
    IMorpho _morpho,
    Id _idleMarketId,
    uint _minReallocationSize
  ) external;

  function checkReallocationNeeded() external view returns (bool, MarketAllocation[] memory);
}

contract ReallocationLogic {
  using MorphoBalancesLib for IMorpho;
  using MarketParamsLib for MarketParams;
  using SharesMathLib for uint256;
  using MathLib for uint256;
  using MorphoLib for IMorpho;
  using UtilsLib for uint256;

  TargetAllocator targetAllocator;
  address VAULT_ADDRESS;
  IMorpho MORPHO;
  Id IDLE_MARKET_ID;
  uint minReallocationSize;

  function setParams(
    TargetAllocator _targetAllocator,
    address _vaultAddress,
    IMorpho _morpho,
    Id _idleMarketId,
    uint _minReallocationSize
  ) public {
    targetAllocator = _targetAllocator;
    VAULT_ADDRESS = _vaultAddress;
    MORPHO = _morpho;
    IDLE_MARKET_ID = _idleMarketId;
    minReallocationSize = _minReallocationSize;
  }

  /** CHECK FUNCTIONS */

  /// @notice Checks if reallocation is needed across all markets based on current and target utilizations.
  /// @return bool Indicates if reallocation is needed.
  /// @return marketAllocations The array of market allocations to be performed if reallocation is needed.
  function checkReallocationNeeded() public view returns (bool, MarketAllocation[] memory) {
    uint256 nbMarkets = IMetaMorpho(VAULT_ADDRESS).withdrawQueueLength();

    MarketParams memory idleMarketParams = MORPHO.idToMarketParams(IDLE_MARKET_ID);
    uint256 idleAssetsAvailable = getAvailableIdleAssets(idleMarketParams);
    for (uint256 i = 0; i < nbMarkets; i++) {
      Id marketId = IMetaMorpho(VAULT_ADDRESS).withdrawQueue(i);
      (bool mustReallocate, MarketAllocation[] memory allocations) = checkMarket(
        marketId,
        idleAssetsAvailable,
        idleMarketParams
      );

      if (mustReallocate) {
        return (true, allocations);
      }
    }

    return (false, new MarketAllocation[](0));
  }

  /// @notice Gets the available assets of the vault currently in the idle market.
  /// @return uint256 Amount of assets available in to be reallocated from the idle market
  function getAvailableIdleAssets(MarketParams memory idleMarketParams) public view returns (uint256) {
    (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets, ) = MORPHO.expectedMarketBalances(
      idleMarketParams
    );

    uint256 supplyShares = MORPHO.supplyShares(IDLE_MARKET_ID, VAULT_ADDRESS);
    uint256 supplyAssets = supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
    uint256 availableLiquidity = totalSupplyAssets - totalBorrowAssets;

    uint256 idleAssetsAvailable = UtilsLib.min(supplyAssets, availableLiquidity);

    return idleAssetsAvailable;
  }

  /// @notice Checks a specific market to determine if reallocation is necessary based on its current utilization and target allocation settings.
  /// @param marketId The market identifier to check.
  /// @param idleAssetsAvailable The amount of assets available in the idle market that can be reallocated.
  /// @param idleMarketParams The market parameters of the idle market.
  /// @return bool Indicates if reallocation is needed for the market.
  /// @return marketAllocations The array of market allocations to be performed if reallocation is needed.
  function checkMarket(
    Id marketId,
    uint256 idleAssetsAvailable,
    MarketParams memory idleMarketParams
  ) public view returns (bool, MarketAllocation[] memory marketAllocations) {
    MarketParams memory marketParams = MORPHO.idToMarketParams(marketId);

    if (marketParams.collateralToken == address(0)) {
      // do not check idle market
      return (false, marketAllocations);
    }

    TargetAllocator.TargetAllocation memory targetAllocation = targetAllocator.getTargetAllocation(marketId);

    // if target allocation for market not set, ignore market
    if (targetAllocation.targetUtilization == 0) {
      return (false, marketAllocations);
    }

    (uint256 totalSupplyAssets, uint256 totalSupplyShares, uint256 totalBorrowAssets, ) = MORPHO.expectedMarketBalances(
      marketParams
    );

    // compute utilization and target total supply assets
    uint256 currentUtilization = (totalBorrowAssets * 1e18) / totalSupplyAssets;

    uint256 targetTotalSupplyAssets = (totalBorrowAssets * 1e18) / targetAllocation.targetUtilization;

    // check if we need to reallocate
    if (currentUtilization > targetAllocation.maxUtilization) {
      // utilization > max target utilization, we should add liquidity from idle
      // compute amount to supply
      // min between the amount available in the idle market and the amount we need to supply
      uint256 amountToSupply = UtilsLib.min(idleAssetsAvailable, targetTotalSupplyAssets - totalSupplyAssets);

      // only reallocate if sufficient amount
      if (amountToSupply < minReallocationSize) {
        return (false, marketAllocations);
      }

      marketAllocations = new MarketAllocation[](2);
      // create allocation: withdraw from idle
      marketAllocations[0] = MarketAllocation({
        marketParams: idleMarketParams,
        // new assets value for the idle market
        // = idleAssetsAvailable minus amount to supply
        assets: idleAssetsAvailable - amountToSupply
      });
      // create allocation: supply all withdrawn to market
      marketAllocations[1] = MarketAllocation({marketParams: marketParams, assets: type(uint256).max});

      return (true, marketAllocations);
    } else if (currentUtilization < targetAllocation.minUtilization) {
      // utilization < min target utilization, we should withdraw to the idle market

      // Keep at least targetAllocation.minLiquidity available
      // this is done because if total supply = 10, total borrow = 5 target utilization = 80% and minLiquidity = 4
      // currently, available liquidity is 10 - 5 = 5 and the current utilization is 50%
      // so to reach 80% we would need to lower the supply to 6.25 => 5/6.25 = 0.8. But if we do that,
      // the remaining liquidity will be 6.25 - 5 = 1.25 which is < 4
      // in this case we will then define the targetTotalSupplyAssets as totalBorrowAssets + targetAllocation.minLiquidity => (5 + 4) = 9
      // this mean a utilization of 55%, better than the current 50% but keeping the minLiquidity as desired
      if (targetTotalSupplyAssets < totalBorrowAssets + targetAllocation.minLiquidity) {
        targetTotalSupplyAssets = totalBorrowAssets + targetAllocation.minLiquidity;
      }

      uint256 supplyShares = MORPHO.supplyShares(marketParams.id(), VAULT_ADDRESS);
      uint256 supplyAssets = supplyShares.toAssetsDown(totalSupplyAssets, totalSupplyShares);
      uint256 availableLiquidity = totalSupplyAssets - totalBorrowAssets;

      // if the available liquidity is less than our threshold, do not change anything
      if (availableLiquidity < targetAllocation.minLiquidity) {
        return (false, marketAllocations);
      }

      uint256 amountToWithdraw = UtilsLib.min(availableLiquidity, totalSupplyAssets - targetTotalSupplyAssets);
      // do not try to withdraw more than what was supplied by the vault
      amountToWithdraw = UtilsLib.min(amountToWithdraw, supplyAssets);

      // only reallocate if sufficient amount
      if (amountToWithdraw < minReallocationSize) {
        return (false, marketAllocations);
      }

      marketAllocations = new MarketAllocation[](2);
      // create allocation: withdraw from the market
      marketAllocations[0] = MarketAllocation({
        marketParams: marketParams,
        // new assets value for the non idle market
        // = current vault supply minus amount to withdraw
        assets: supplyAssets - amountToWithdraw
      });
      // create allocation: supply all withdrawn to idle market
      marketAllocations[1] = MarketAllocation({marketParams: idleMarketParams, assets: type(uint256).max});

      return (true, marketAllocations);
    }

    return (false, marketAllocations);
  }
}

contract TargetAllocator {
  using MorphoBalancesLib for IMorpho;
  using MarketParamsLib for MarketParams;
  using SharesMathLib for uint256;
  using MathLib for uint256;
  using MorphoLib for IMorpho;
  using UtilsLib for uint256;

  struct TargetAllocation {
    uint64 maxUtilization; // percentage with 18 decimals. Max = ~1844% with uint64
    uint64 targetUtilization; // percentage with 18 decimals. Max = ~1844%  with uint64
    uint64 minUtilization; // percentage with 18 decimals. Max = ~1844% with uint64
    uint256 minLiquidity; // absolute amount in wei
  }

  /// @notice this is the idle market from/to which we will reallocate, set in the ctor
  Id public immutable IDLE_MARKET_ID;

  /// @notice the metamorpho vault address, set in the ctor
  address public immutable VAULT_ADDRESS;

  /// @notice the Morpho blue contract, set in the ctor
  IMorpho public immutable MORPHO;

  /// @notice the last reallocation performed by the keeperCall function
  uint256 public lastReallocationTimestamp;

  /// @notice the minimum delay between two reallocation by the keeperCall function
  uint256 public minDelayBetweenReallocations;

  /// @notice mapping of marketId => target allocation parameters
  /// set in the constructor but can be modified by any of the vault allocators
  mapping(Id => TargetAllocation) public targetAllocations;

  /// @notice the minimum reallocation size, used to not broadcast a transaction for moving dust amount of an asset
  uint256 public minReallocationSize;

  /// @notice the keeper (bot) address that will be used to automatically call the keeperCheck and keeperCall functions
  address public keeperAddress;

  /// @notice Initializes a new TargetAllocator contract with specific market target allocations and operational settings.
  /// @param _idleMarketId The market identifier for the idle market.
  /// @param _vault The address of the Morpho vault.
  /// @param _minDelayBetweenReallocations The minimum delay between two reallocation actions.
  /// @param _minReallocationSize The minimum size of assets to be considered for reallocation.
  /// @param _keeperAddress The address of the keeper responsible for triggering reallocations.
  /// @param _marketIds An array of market identifiers for which target allocations are being set.
  /// @param _targetAllocations An array of target allocation settings corresponding to the market identifiers.
  constructor(
    bytes32 _idleMarketId,
    address _vault,
    uint256 _minDelayBetweenReallocations,
    uint256 _minReallocationSize,
    address _keeperAddress,
    bytes32[] memory _marketIds,
    TargetAllocation[] memory _targetAllocations
  ) {
    require(
      _marketIds.length == _targetAllocations.length,
      "TargetAllocator: length mismatch [_marketIds, _targetAllocations]"
    );

    IDLE_MARKET_ID = Id.wrap(_idleMarketId);
    VAULT_ADDRESS = _vault;
    MORPHO = IMetaMorpho(VAULT_ADDRESS).MORPHO();
    minDelayBetweenReallocations = _minDelayBetweenReallocations;
    lastReallocationTimestamp = 1; // initialize storage slot to cost less for next usage
    minReallocationSize = _minReallocationSize;
    keeperAddress = _keeperAddress;

    for (uint256 i = 0; i < _marketIds.length; ) {
      targetAllocations[Id.wrap(_marketIds[i])] = _targetAllocations[i];

      // use less gas
      unchecked {
        ++i;
      }
    }
  }

  function getTargetAllocation(Id id) public view returns(TargetAllocation memory) {
    return targetAllocations[id];
  }

  /** ONLY ALLOCATORS SETTER FUNCTIONS */

  /// @notice Sets the minimum delay between reallocations.
  /// @param _newValue The new minimum delay value in seconds.
  function setMinDelayBetweenReallocations(uint256 _newValue) external {
    require(isVaultAllocator(msg.sender), "TargetAllocator: caller not allowed");
    minDelayBetweenReallocations = _newValue;
  }

  /// @notice Sets the minimum size for reallocations to avoid transactions for negligible amounts.
  /// @param _newValue The new minimum reallocation size in the asset's smallest unit.
  function setMinReallocationSize(uint256 _newValue) external {
    require(isVaultAllocator(msg.sender), "TargetAllocator: caller not allowed");
    minReallocationSize = _newValue;
  }

  /// @notice Sets the keeper address responsible for triggering reallocations.
  /// @param _newValue The new address of the keeper.
  function setKeeperAddress(address _newValue) external {
    require(isVaultAllocator(msg.sender), "TargetAllocator: caller not allowed");
    keeperAddress = _newValue;
  }

  /// @notice Sets target allocation parameters for a given market.
  /// @param marketId The market identifier for which to set the target allocation.
  /// @param targetAllocation The target allocation parameters including max, target, and min utilization percentages, and min liquidity.
  function setTargetAllocation(bytes32 marketId, TargetAllocation memory targetAllocation) external {
    require(isVaultAllocator(msg.sender), "TargetAllocator: caller not allowed");
    targetAllocations[Id.wrap(marketId)] = targetAllocation;
  }

  /** CHECK FUNCTIONS */

  /// @notice Checks if reallocation is needed across all markets based on current and target utilizations.
  /// @return bool Indicates if reallocation is needed.
  /// @return marketAllocations The array of market allocations to be performed if reallocation is needed.
  function checkReallocationNeeded(bytes memory checkerBytecode) public /*view*/ returns (bool, MarketAllocation[] memory) {
      // deploy
      address child;
      assembly{
        mstore(0x0, checkerBytecode)
        child := create(0,0xa0, calldatasize())
      }
      IReallocationLogic logic = IReallocationLogic(child);
      
      // set params
      logic.setParams(this, VAULT_ADDRESS, MORPHO, IDLE_MARKET_ID, minReallocationSize);

      return logic.checkReallocationNeeded();
  }

  /** KEEPER FUNCTIONS */

  /// @notice Checks if a reallocation action is necessary and returns the encoded call data to perform the reallocation if so.
  /// @return bool Indicates if a reallocation action should be taken.
  /// @return call The encoded call data to execute the reallocation.
  function keeperCheck(bytes memory checkerBytecode) external /*view*/ returns (bool, bytes memory call) {
    if (lastReallocationTimestamp + minDelayBetweenReallocations > block.timestamp) {
      return (false, call);
    }

    (bool mustReallocate, MarketAllocation[] memory allocations) = checkReallocationNeeded(checkerBytecode);

    if (mustReallocate) {
      call = abi.encodeCall(IMetaMorphoBase.reallocate, allocations);
      return (true, call);
    }

    // return false for the keeper bot
    return (false, call);
  }

  /// @notice Executes a reallocation action based on call data provided by the keeperCheck function.
  /// @param call The encoded call data for the reallocation action.
  function keeperCall(bytes calldata call) external {
    require(msg.sender == keeperAddress || isVaultAllocator(msg.sender), "TargetAllocator: caller not allowed");

    (bool success, bytes memory result) = VAULT_ADDRESS.call(call);
    if (success) {
      lastReallocationTimestamp = block.timestamp;
    } else {
      _getRevertMsg(result);
    }
  }

  /// @notice Checks if the sender is an authorized vault allocator.
  /// @param sender The address to check.
  /// @return bool Indicates if the address is an authorized allocator.
  function isVaultAllocator(address sender) public view returns (bool) {
    return IMetaMorpho(VAULT_ADDRESS).isAllocator(sender);
  }

  error CallError(bytes innerError);

  /// @dev Extracts a revert message from failed call return data.
  /// @param _returnData The return data from the failed call.
  function _getRevertMsg(bytes memory _returnData) internal pure {
    // If the _res length is less than 68, then
    // the transaction failed with custom error or silently (without a revert message)
    if (_returnData.length < 68) {
      revert CallError(_returnData);
    }

    assembly {
      // Slice the sighash.
      _returnData := add(_returnData, 0x04)
    }
    revert(abi.decode(_returnData, (string))); // All that remains is the revert string
  }
}