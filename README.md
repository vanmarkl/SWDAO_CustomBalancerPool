[1inch]: https://app.1inch.io/
[am3crv]: https://polygon.curve.fi/aave
[amm]: https://medium.com/balancer-protocol/what-is-an-automated-market-maker-amm-588954fc5ff7
[balancer]: https://balancer.fi/
[bpt]: https://help.balancer.finance/en/articles/4418446-what-are-balancer-pool-tokens
[constprod]:
https://docs.uniswap.org/protocol/V2/concepts/protocol-overview/glossary#constant-product-formula
[controller]:
https://github.com/Peter-Flynn/SWDAO_TokenPriceManager-Controller/blob/master/contracts/interfaces/ITokenPriceControllerMinimal.sol
[crvEURTUSD]: https://polygon.curve.fi/eurtusd
[cbp]: contracts/CustomBalancerPool.sol
[CustomBalancerPool.sol]: contracts/CustomBalancerPool.sol
[exstor]: contracts/ExtraStorage.sol
[fc]: https://book.getfoundry.sh/reference/forge/forge-create.html
[fl]: https://book.getfoundry.sh/reference/forge/forge-create.html#linker-options
[foundry]: https://github.com/foundry-rs/foundry
[instructions]: https://github.com/foundry-rs/foundry#installation
[matcha]: https://matcha.xyz/
[phantom]:
https://docs.balancer.fi/products/balancer-pools/boosted-pools#phantom-pool-tokens-phantom-bpt
[polygonscan]: https://polygonscan.com/
[polygon pos]: https://polygon.technology/solutions/polygon-pos
[QMB]: https://www.swdao.org/products/quantum-momentum
[remix]: https://remix.ethereum.org/
[SWAP]: https://www.swdao.org/products/alpha-portfolio
[swd]: https://www.swdao.org/products/swd-token
[SWYF]: https://www.swdao.org/products/yield-fund
[sw&nbsp;dao]: https://www.swdao.org/
[test]: contracts/test
[tpm]:
https://github.com/Peter-Flynn/SWDAO_TokenPriceManager-Controller/blob/master/contracts/interfaces/ITokenPriceManagerMinimal.sol
[transparent proxy]:
https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.4/contracts/proxy/TransparentUpgradeableProxy.sol
[uni]: https://docs.uniswap.org/protocol/V2/concepts/protocol-overview/how-uniswap-works
[vault]: lib/balancer-v2-monorepo/pkg/vault/contracts/interfaces/IVault.sol
[verify]: contracts/verify

<p align="center">
	<img src=".github/images/SW DAO Logo Vertical.png#gh-light-mode-only"
		alt="SW DAO logo" width="15%" />
	<img src=".github/images/SW DAO Logo Vertical Dark.png#gh-dark-mode-only"
		alt="SW DAO logo" width="15%" />
	<br />
	<h1 align="center">
		Custom <a href="https://balancer.fi/">Balancer</a> Pool<br />
		for <a href="https://www.swdao.org/">SW&nbsp;DAO</a> on
		<a href="https://polygon.technology/solutions/polygon-pos">Polygon&nbsp;PoS</a>
	</h1>
</p>

A custom liquidity, and market solution utilizing [Balancer][] – offers more
accurate pricing for [SW&nbsp;DAO][] products, weighs
[SWD][]'s price against a basket of assets, and packages
the entire liquidity pool within an easily-purchasable token.
> **Note**<br />
> Concessions were made to comply with Solidity limitations, and time constraints (ex. contract
> emits few events, is not gas efficient, and uses an external library). Future versions of this
> contract should use separate contracts per function, with a local singleton for
  [`onSwap()`](#balancer-functions).
## Usage
> Documentation at this time is minimal: just enough to facilitate audits.<br />
> More "user-friendly" documentation is in the works.

Typically, the end-user will never interact with the pool directly.
["User" functions](#user-functions) serve to assist in requests for data, and
["owner" functions](#owner-functions) assist with pool management, but all functionality relevant
to an end-user is abstracted away through [Balancer][]'s interfaces. As such, all end-user
functionality is accessible through [Balancer][], [Matcha][], and [1inch][], but can also be made
available directly through a custom website.
### Functionality
- Creates a fully-functional [Balancer][] pool, with non-standard features.
- Allows tokens to be added to, or removed from the pool at will.
- Manages tokens within configurable categories.
  - [SW&nbsp;DAO][] products ([SWAP][], [SWYF][], [QMB][], etc.)
  - Common tokens (wETH, LINK, wMATIC, etc.)
  - National currencies (USDC, DAI, [am3CRV][], [crvEURTUSD][], etc.)

  Any token may be placed within these three categories.
- Allows for changing the weights of these categories, relative to one-another.
- Allows for changing the weights of individual tokens, relative to other tokens within the same
  category.
- Maintains the requested weights using a flat, configurable fee/bonus for trades – offering
  better prices to traders who bring the pool into balance.
- Utilizes [TPM][]s for tokens (except for [SWD][], and the [BPT][]), maintaining fair pricing
  regardless of balances within the pool.
- Prices [SWD][] in a [constant-product formula][constprod] against the value of all other assets
  combined! Making for highly efficient use of liquidity.
- Allows the [BPT][] to be traded [like any other token][phantom] – with a custom name, and symbol.
- Implements a "block&nbsp;lock", preventing flash-loan attacks (although no attack vector is
  currently known).
- Implements a "swap&nbsp;lock" which can be engaged by the pool's owner to temporarily disable
  swaps. Also implements a "safe withdrawal" mode for [BPT][] holders while the pool is locked.
- Transparently pays fees due to the [Balancer protocol][balancer].
- Designed to be implemented behind a [transparent proxy][], making it upgradeable without
  requiring manual intervention from end-users.
- Implements contract versioning to assist with upgrades.
- Implements contract ownership – blocking regular users from sensitive functions, and allowing
  for safe transfer of ownership.

See "[Swap Functionality](#swap-functionality)" below for more detail on how tokens are priced
within the pool.
### Balancer Functions
These are only callable by the [Balancer vault][vault], and must be accessed using the [vault][]'s
functionality.
- `onJoinPool(...)`<br />
Standard [Balancer][] interface for joining a pool as a liquidity provider. Used in a nonstandard
fashion, and doesn't allow joins from end-users. Instead, joins are performed as standard swaps.
- `onExitPool(...)`<br />
Standard [Balancer][] interface for exiting a pool as a liquidity provider, pulling said liquidity.
Used in a nonstandard fashion, and only allows end-user exits when the pool is "swap locked".
Instead, typical exits are performed as standard swaps.
- `onSwap(...)`<br />
Standard [Balancer][] interface for swapping tokens within the pool. Please see
"[Swap Functionality](#swap-functionality)" below for more detail on how swaps are performed.

See [CustomBalancerPool.sol][] for more detail.
### User Functions
- `getValue()`<br />
Gives the USD value of both the [BPT][], and [SWD][] (with 18 decimals of precision).
- `isLocked()`<br />
Detects whether or not the "swap lock" is engaged.
- `getCirculatingSupply()`<br />
Gives the number of [BPT][] in circulation (with 18 decimals of precision).

See [CustomBalancerPool.sol][] for less relevant functions, and more detail.
### Owner Functions
- `constructor()`<br />
Only exists for compatibility, and goes unused. Never called when run behind a
[transparent proxy][].
- `initialize(string,string)`<br />
Fills in for the `constructor()`, and works behind the [proxy][transparent proxy]. Can only be
called once per contract "version".
- `tokensAdd(IERC20[],TokenCategory[],uint8[])`<br />
Adds tokens to the pool, with specified categories, and weights. Tokens must have [TPM][]s within
the designated [controller][].
- `tokensRemove(IERC20[])`<br />
Removes tokens from the pool. Each token must have a zero-balance within the pool.
- `setBalanceFee(uint8)`<br />
Sets the flat fee/bonus used to incentivize traders to keep the pool balanced, according to the configured weights.
- `setCategoryWeights(uint8[3])`<br />
Sets the weights of each category, relative to one another.
- `setTokenWeights(IERC20[],uint8[])`<br />
Sets the weights of the requested tokens. Weights are relative to all other tokens within a given
token's category.
- `toggleSwapLock()`<br />
Toggles the state of the "swap lock". The lock can always be toggled to "on", but toggling "off"
requires that the pool be properly initialized.
- `ownerTransfer(address)`<br />
Transfers the pool's ownership from its current owner, to the new address. Must be finalized with
`ownerConfirm()` within 36 hours.
- `ownerConfirm()`<br />
Finalizes an ownership transfer.
- `withdrawToken(address)`<br />
Rescues mis-sent ERC20 tokens from the contract address.

See [CustomBalancerPool.sol][] for more detail.
## Development
This repository utilizes [Foundry][] for its developer environment. As a result, building/testing
of contracts is  relatively simple.
### Building
1. Install [Foundry][] according to its [instructions][].
2. `git clone` this repo. with `--recurse-submodules` enabled.
3. `cd` into the cloned repo. and run `forge build`.

### Testing
1. Follow the instructions in the [section](#building) above.
2. Instead of `forge build`, run `forge test`.

Tests can be found in the [test][] folder, and are written in Solidity. This repo. has configured
[Foundry][] to fork the [Polygon PoS][] chain during testing. More thorough fuzz testing can be
done by passing the `FOUNDRY_PROFILE=fulltest` environment variable before `forge test`.

## Deployment
A few methods are available for contract deployment, although doing so is not recommended. The
[`CustomBalancerPool`][cbp] is designed to run behind a [transparent proxy][]. Additionally,
deploying, and initializing the contract will register it with the [Balancer vault][vault],
connecting it to [Balancer][]'s swap interface. **Only continue with deployment if you're certain
that's what you need.**
### Using [Foundry][]
1. Follow the instructions in the ["Building" section](#building) above.
2. Run `forge build`, as requested.
3. Use [`forge create`][fc] to deploy the [`ExtraStorage` library][exstor].
4. Use [`forge create`][fc] with [`--libraries`][fl] to deploy the [`CustomBalancerPool`][cbp].
```
$ forge build
$ forge create <args> contracts/ExtraStorage.sol:ExtraStorage
$ forge create <args> --libraries contracts/ExtraStorage.sol:ExtraStorage:<address> contracts/CustomBalancerPool.sol:CustomBalancerPool
```
### Using [Remix][]
This repo. provides flattened contract code in folders titled "[verify][]". These files correspond
to each of the major contracts, and can be safely ported into [Remix][] for testing, and
deployment. They're also intended for use in [Polygonscan][] verification. Deploy the
[`ExtraStorage` library][exstor] first, then point [Remix][] to include the deployed library's
address during deployment of the [`CustomBalancerPool`][cbp].
## Swap Functionality
> This section has been placed at the end, due to its length.

The swap implementation is unique, and is composed internally using separate [AMM][] methods:
1. The first method applies to all tokens that are not the [BPT][], or [SWD][].
	- Tokens are bought and sold for the fair price dictated by the [TPM][].
	- Buy versus sell price can be reported differently by the [TPM][].
	- Tokens may run out entirely, and prices do not change according to balance proportions
	  (unlike [Uniswap's constant-product method][uni]).
	- Tokens are maintained according to the set weights using a flat fee/bonus dictated by
	  the configured "balance fee". A user bringing the pool back into balance will receive a
	  bonus (reducing the [BPT][]'s price), whereas a user bringing it out of balance will pay a
	  fee (increasing the [BPT][]'s price). Balance is incentivized by offering rates different
	  from those in the wider market.
	- Fees due to the [Balancer protocol][balancer] are calculated by comparing the final output
	  to a hypothetical, feeless transaction.
2. The second method applies to [SWD][].
	- [SWD][]'s price is calculated using the [constant-product method][constprod]
	  ([like Uniswap][uni]).
	- Rather than calculating against a single token (ex. WETH, USDC, etc.), [SWD][] is compared to
	  the entire sum of all other tokens in the pool (in USD).<br />
	  With the [BPT][] being `Token_0`, and [SWD][] being `Token_1`:
	  ```
	  Balance:        USD Sum:        Constant:
	
	                  Token_2
	  SWD        ×    ...        =    K
	                  Token_N
	  ```
	  Alternatively:<br />
	  > ([SWD][]&nbsp;Price)×([SWD][]&nbsp;Balance)&nbsp;=
	  (Token_2&nbsp;Price)×(Token_2&nbsp;Balance)&nbsp;+ ...&nbsp;+
	  (Token_N&nbsp;Price)×(Token_N&nbsp;Balance)
   - Summing the USD value of all tokens can be gas-expensive, therefore future versions
	  of this contract should seek to make this process as efficient as possible, and care
	  should be taken when adding more tokens to the pool. A hard cap of 50 tokens has been set.
3. The final method applies to the [BPT][].
	- Like [SWD][], the [BPT][]'s price is found through the summation of all value within the
	  pool, but rather than changing with balance proportions, the total pool value is simply
	  divided by the [BPT][]'s circulating supply.
	  ```
	  USD Sum:        Balance:                     USD Price:

	  Token_2
	  ...        /    (Circulating Supply)    =    BPT
	  Token_N
	  ```
	- The [BPT][]'s circulating supply is found by subtracting the pool's balance from the 
	  total supply, and then adding those tokens due as fees to the Balancer protocol, but not
	  yet issued.
	  > (Circulating&nbsp;Supply)&nbsp;= (Total&nbsp;Supply)&nbsp;- (Pool&nbsp;Balance)&nbsp;+
	  (Due&nbsp;Protocol&nbsp;Fees)
	- The process of the pool owner joining the pool with
	  [`JoinKindPhantom.INIT`][CustomBalancerPool.sol] mints the initial supply of [BPT][], and
	  deposits the initial balance within the pool. The total balance remaining in the pool owner's
	  wallet will equate 1-to-1 with every USD (in value) deposited to the pool, excluding the
	  value of the [SWD][]. This gives the [BPT][] an initial value of $1.
	- As [BPT][] are accounted for as they enter/leave the pool, the price of the [BPT][] will
	  remain constant for such transactions.<br />
	  The price of the [BPT][] only changes if:
		- The underlying tokens change in value.
		- Trades are made with the [SWD][] balance (thus changing [SWD][]'s value).
		- The pool accumulates fees, or grants trade bonuses.

	  This makes the [BPT][]'s performance as an asset easy to understand for the end user.
	- Intuitively, one might expect that the [BPT][] should be valued using double the pool's total
	  value, in order to account for the value of the pool's [SWD][]. However, this would be an
	  error, as shown in the following scenario:
		1. A user owns all circulating [BPT][].
		2. That user sells half their [BPT][] to purchase all tokens except the [SWD][].
		3. The user then sells zero [BPT][] to purchase all the [SWD][] which are now worth
		   nothing.
		4. The user retains half their original [BPT][], while the pool is now empty.

	  Accounting for the [BPT][]'s price properly avoids such a possibility.

All complexity is abstracted away from the end user, and these solutions are compatible with DEx
aggregators. Trades from [SWD][] to the [BPT][] are not allowed directly, acting as an artificial
bias towards [SWD][]'s positive price-action.
