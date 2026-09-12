// Sources flattened with hardhat v2.20.0 https://hardhat.org

// SPDX-License-Identifier: GPL-3.0-or-later AND MIT

// File contracts/interfaces/IAsset.sol

// Original license: SPDX_License_Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity >=0.7.0;

/**
 * @dev This is an empty interface used to represent either ERC20-conforming token contracts or ETH (using the zero
 * address sentinel value). We're just relying on the fact that `interface` can be used to declare new address-like
 * types.
 *
 * This concept is unrelated to a Pool's Asset Managers.
 */
interface IAsset {
    // solhint-disable-previous-line no-empty-blocks
}


// File contracts/interfaces/IVault.sol

// Original license: SPDX_License_Identifier: GPL-3.0-or-later
pragma solidity >=0.7.0;

interface IVault {

    // Swaps
    //
    // Users can swap tokens with Pools by calling the `swap` and `batchSwap` functions. To do this,
    // they need not trust Pool contracts in any way: all security checks are made by the Vault. They must however be
    // aware of the Pools' pricing algorithms in order to estimate the prices Pools will quote.
    //
    // The `swap` function executes a single swap, while `batchSwap` can perform multiple swaps in sequence.
    // In each individual swap, tokens of one kind are sent from the sender to the Pool (this is the 'token in'),
    // and tokens of another kind are sent from the Pool to the recipient in exchange (this is the 'token out').
    // More complex swaps, such as one token in to multiple tokens out can be achieved by batching together
    // individual swaps.
    //
    // There are two swap kinds:
    //  - 'given in' swaps, where the amount of tokens in (sent to the Pool) is known, and the Pool determines (via the
    // `onSwap` hook) the amount of tokens out (to send to the recipient).
    //  - 'given out' swaps, where the amount of tokens out (received from the Pool) is known, and the Pool determines
    // (via the `onSwap` hook) the amount of tokens in (to receive from the sender).
    //
    // Additionally, it is possible to chain swaps using a placeholder input amount, which the Vault replaces with
    // the calculated output of the previous swap. If the previous swap was 'given in', this will be the calculated
    // tokenOut amount. If the previous swap was 'given out', it will use the calculated tokenIn amount. These extended
    // swaps are known as 'multihop' swaps, since they 'hop' through a number of intermediate tokens before arriving at
    // the final intended token.
    //
    // In all cases, tokens are only transferred in and out of the Vault (or withdrawn from and deposited into Internal
    // Balance) after all individual swaps have been completed, and the net token balance change computed. This makes
    // certain swap patterns, such as multihops, or swaps that interact with the same token pair in multiple Pools, cost
    // much less gas than they would otherwise.
    //
    // It also means that under certain conditions it is possible to perform arbitrage by swapping with multiple
    // Pools in a way that results in net token movement out of the Vault (profit), with no tokens being sent in (only
    // updating the Pool's internal accounting).
    //
    // To protect users from front-running or the market changing rapidly, they supply a list of 'limits' for each token
    // involved in the swap, where either the maximum number of tokens to send (by passing a positive value) or the
    // minimum amount of tokens to receive (by passing a negative value) is specified.
    //
    // Additionally, a 'deadline' timestamp can also be provided, forcing the swap to fail if it occurs after
    // this point in time (e.g. if the transaction failed to be included in a block promptly).
    //
    // If interacting with Pools that hold WETH, it is possible to both send and receive ETH directly: the Vault will do
    // the wrapping and unwrapping. To enable this mechanism, the IAsset sentinel value (the zero address) must be
    // passed in the `assets` array instead of the WETH address. Note that it is possible to combine ETH and WETH in the
    // same swap. Any excess ETH will be sent back to the caller (not the sender, which is relevant for relayers).
    //
    // Finally, Internal Balance can be used when either sending or receiving tokens.

    enum SwapKind { GIVEN_IN, GIVEN_OUT }

    /**
     * @dev Data for a single swap executed by `swap`. `amount` is either `amountIn` or `amountOut` depending on
     * the `kind` value.
     *
     * `assetIn` and `assetOut` are either token addresses, or the IAsset sentinel value for ETH (the zero address).
     * Note that Pools never interact with ETH directly: it will be wrapped to or unwrapped from WETH by the Vault.
     *
     * The `userData` field is ignored by the Vault, but forwarded to the Pool in the `onSwap` hook, and may be
     * used to extend swap behavior.
     */
    struct SingleSwap {
        bytes32 poolId;
        SwapKind kind;
        IAsset assetIn;
        IAsset assetOut;
        uint256 amount;
        bytes userData;
    }

    /**
     * @dev All tokens in a swap are either sent from the `sender` account to the Vault, or from the Vault to the
     * `recipient` account.
     *
     * If the caller is not `sender`, it must be an authorized relayer for them.
     *
     * If `fromInternalBalance` is true, the `sender`'s Internal Balance will be preferred, performing an ERC20
     * transfer for the difference between the requested amount and the User's Internal Balance (if any). The `sender`
     * must have allowed the Vault to use their tokens via `IERC20.approve()`. This matches the behavior of
     * `joinPool`.
     *
     * If `toInternalBalance` is true, tokens will be deposited to `recipient`'s internal balance instead of
     * transferred. This matches the behavior of `exitPool`.
     *
     * Note that ETH cannot be deposited to or withdrawn from Internal Balance: attempting to do so will trigger a
     * revert.
     */
    struct FundManagement {
        address sender;
        bool fromInternalBalance;
        address payable recipient;
        bool toInternalBalance;
    }

}


// File contracts/interfaces/AggregatorV3Interface.sol

// Original license: SPDX_License_Identifier: MIT
pragma solidity >=0.6.0;

interface AggregatorV3Interface {

  function decimals()
    external
    view
    returns (
      uint8
    );

  function description()
    external
    view
    returns (
      string memory
    );

  function version()
    external
    view
    returns (
      uint256
    );

  function getRoundData(
    uint80 _roundId
  )
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

}


// File contracts/SlippageRequester.sol

// Original license: SPDX_License_Identifier: GPL-3.0-or-later
pragma solidity >=0.7.0;



contract SlipageRequester {
    address public balancerAddress;

    constructor(address balancerAddress_) {
        balancerAddress = balancerAddress_;
    }

    /**
    * @dev Fetches the ChainLink token price
    * @param dataFeed_ the address of the Chainlink data feed
    * @return the token price 
    *
    * https://docs.chain.link/data-feeds/price-feeds/addresses?network=ethereum&page=1
    */
    function getChainlinkPrice(address dataFeed_)
        external
        view
        returns (int256)
    {
        return _getChainlinkPrice(dataFeed_);
    }

    /**
     * @dev Utility returning the token selector for `getChainlinkPrice`
     */
    function getChainLinkPriceselector() external pure returns (bytes4) {
        return this.getChainlinkPrice.selector;
    }

    /**
     * @dev Utility returning the token selector for `getSlippage`
     */
    function getFunctionSelector() external pure returns (bytes4) {
        return this.getSlippage.selector;
    }

    /**
     * @dev Utility returning the token selector for `getSwapValue`
     */
    function getSwapValueSelector() external pure returns (bytes4){
        return this.getSwapValue.selector;
    }

    /**
     * @dev Fetches the slippage
     * @param poolId_ the unique identifier of the requested token pool
     * @param kind_ ∈ {GIVEN_IN, GIVEN_OUT} = uint8 {0x00, 0x01}
     * @param tokenA_ the address of the firs token in the pair
     * @param tokenB_ the address of the second token
     * @param amount_ the sum x token decimals
     * @param sender_ a valid EOA's address
     * @param dataFeedA_ the address of the Chainlink data feed for token A
     * @param dataFeedB_ the address of the Chainlink data feed for token B
     * @return tuple (tokenA in USD, tokenB in USD, slippage in USD, decimalsA, decimalsB)
     */
    function getSlippage(
        bytes32 poolId_,
        IVault.SwapKind kind_,
        address tokenA_,
        address tokenB_,
        uint256 amount_,
        address sender_,
        address dataFeedA_,
        address dataFeedB_
    )
        external
        returns (
            uint256,
            uint256,
            int256,
            uint8,
            uint8
        )
    {
        // 1. Get the estimation from the swap dry run
        uint256 returnValue = _getSwapValue(
            poolId_,
            kind_,
            tokenA_,
            tokenB_,
            amount_,
            sender_
        );

        // 2. Get the token prices
        int256 tokenAPrice = _getChainlinkPrice(dataFeedA_);
        int256 tokenBPrice = _getChainlinkPrice(dataFeedB_);

        // 3. Calculate the expected and observed values in USD
        // uint256 expected = (amount_ * uint256(tokenAPrice)) /
        //     (10**AggregatorV3Interface(dataFeedA_).decimals());
        // uint256 actual = (returnValue * uint256(tokenBPrice)) /
        //     (10**AggregatorV3Interface(dataFeedB_).decimals());

        // 4. Return the values
        return (
            uint256(tokenAPrice) * amount_, // Token A in USD
            uint256(tokenBPrice) * returnValue, // Token B in USD
            int256(0), // Slippage in USD - ignore this field
            AggregatorV3Interface(dataFeedA_).decimals(),
            AggregatorV3Interface(dataFeedB_).decimals()
        );
    }

    /**
     * @dev Querries the Balancer contract
     * @param poolId_ the unique identifier of the requested token pool
     * @param kind_ ∈ {GIVEN_IN, GIVEN_OUT}
     * @param tokenA_ the address of the firs token in the pair
     * @param tokenB_ the address of the second token
     * @param amount_ the sum x token decimals
     * @param sender_ a valid EOA's address
     * @return the value of token B swapped for token A
     */
    function getSwapValue(
        bytes32 poolId_,
        IVault.SwapKind kind_,
        address tokenA_,
        address tokenB_,
        uint256 amount_,
        address sender_
    ) external returns (uint256) {
        return
            _getSwapValue(poolId_, kind_, tokenA_, tokenB_, amount_, sender_);
    }

    /**
     * @dev Retrievs the token price from the ChainLink Oracle
     * @param dataFeed_ the address of the token price feed
     * @return the current token price in USD
     */
    function _getChainlinkPrice(address dataFeed_)
        private
        view
        returns (int256)
    {
        (
            ,
            /* uint80 roundID */
            int256 answer,   
            , /*uint startedAt*/
            , /*uint timeStamp*/
            /*uint80 answeredInRound*/
        ) = AggregatorV3Interface(dataFeed_).latestRoundData();

        return answer;
    }

    function _getSwapValue(
        bytes32 poolId_,
        IVault.SwapKind kind_,
        address tokenA_,
        address tokenB_,
        uint256 amount_,
        address sender_
    ) private returns (uint256) {
        // 1. Populate param singleSwap
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: poolId_,
            kind: kind_,
            assetIn: IAsset(address(tokenA_)),
            assetOut: IAsset(address(tokenB_)),
            amount: amount_,
            userData: bytes("")
        });
        // 2. Populate param funds
        IVault.FundManagement memory funds = IVault.FundManagement({
            sender: sender_,
            fromInternalBalance: false,
            recipient: payable(address(0)),
            toInternalBalance: false
        });

        // 3. Prepare the function call data
        bytes memory data = abi.encodeWithSelector(
            bytes4(
                keccak256(
                    "querySwap((bytes32,uint8,address,address,uint256,bytes),(address,bool,address,bool))"
                )
            ),
            singleSwap,
            funds
        );

        // 4. Execute the function call using .call()
        (bool success, bytes memory returnData) = balancerAddress.call(data);
        require(success, "Function call failed");

        // 5. Decode from bytes32 to uint256
        uint256 returnValue;
        assembly {
            returnValue := mload(add(returnData, 32))
        }

        // 6. return the value
        return returnValue;
    }
}