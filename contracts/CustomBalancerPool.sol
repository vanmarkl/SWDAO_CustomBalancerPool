// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGeneralPool} from "@balancer-labs/v2-vault/contracts/interfaces/IGeneralPool.sol";
import {BalancerPoolToken} from "@balancer-labs/v2-pool-utils/contracts/BalancerPoolToken.sol";
import {ITokenPriceControllerDefault} from
	"token-price-manager/contracts/interfaces/ITokenPriceControllerDefault.sol";
import {ITokenPriceManagerMinimal} from
	"token-price-manager/contracts/interfaces/ITokenPriceManagerMinimal.sol";
import "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol";

import "./ExtraStorage.sol";
import "./ICommonStructs.sol";

/// @title SW DAO Balancer pool
/// @author Peter T. Flynn
/// @notice In order to allow swaps, the contract creator must call initialize(), tokensAdd(),
/// and setCategoryWeights(). Additionally, the owner must seed the pool by joining it with 
/// type [JoinKindPhantom.INIT], and finally calling toggleSwapLock().
/// @dev This contract is designed to operate behind a proxy, and must be initialized before use.
/// Constants require adjustment for deployment outside Polygon.
/// Concessions were made to comply with Solidity limitations, and time constraints
/// (ex. contract emits few events, is not gas efficient, and uses an external library).
/// Future versions of this contract should use separate contracts per function, with a local
/// singleton for onSwap(). [CONTRACT_VERSION] must be incremented every time a new contract
/// version necessitates a call to initialize().
contract CustomBalancerPool is IGeneralPool, BalancerPoolToken, ICommonStructs {
	IVault constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
	IERC20 constant SWD = IERC20(0xaeE24d5296444c007a532696aaDa9dE5cE6caFD0);
	ITokenPriceControllerDefault constant ORACLE =
		ITokenPriceControllerDefault(0x8A46Eb6d66100138A5111b803189B770F5E5dF9a);

	// 2^96 - 1 (~80 billion at 18-decimal precision)
	uint constant MAX_POOL_BPT = 0xffffffffffffffffffffffff;
	// 1e18 corresponds to 1.0, or a 100% fee
	// Set to the minimum for compatibility with Balancer interfaces. Actual fee is dynamic,
	// and changes on a per-token basis. [dueProtocolFees] are calculated at time of swap.
	uint256 constant SWAP_FEE_PERCENTAGE = 1e12; // 0.0001%
	// Always known, set at the first run of initialize()
	uint constant INDEX_BPT = 0;
	// Always known, set at the first run of initialize()
	uint constant INDEX_SWD = 1;
	// Named for readability
	uint8 constant UINT8_MAX = type(uint8).max;
	// Useful in common, fixed-point math - named for readability
	uint constant EIGHTEEN_DECIMALS = 1e18;

	// INIT, and COLLECT_PROTOCOL_FEES are standard, but TOP_UP_BPT has been added for the
	// highly-unlikely case in which the pool runs out of BPT for trading
	enum JoinKindPhantom { INIT, COLLECT_PROTOCOL_FEES, TOP_UP_BPT }
	// Balancer standard
	enum ExitKindPhantom { EXACT_BPT_IN_FOR_TOKENS_OUT }

	// Must be incremented whenever a new initialize() function is needed for an implementation
	uint16 constant CONTRACT_VERSION = 100; // Version 1.00;

	// SEE ICommonStructs.sol, AND ExtraStorage.sol FOR FURTHER DOCUMENTATION

	// Gas-saving storage slot
	Slot6 private slot6;
	// New owner for ownership transfer
	address private ownerNew;
	// Typically stored in [slot6.balanceFee], but said variable is also used for locking the
	// contract against swaps. In such an event, [balanceFeeCache] is used to store the original
	// value.
	uint8 private balanceFeeCache;
	// Timestamp for ownership transfer timeout
	uint private ownerTransferTimeout;
	// The Balancer-determined swap fee, paid to Balancer. Can be updated with
	// updateCachedProtocolSwapFeePercentage() by any caller.
	uint private cachedProtocolSwapFeePercentage;
	// The BPT balance owed to Balancer, which can be paid by any user joining the pool
	// with type [JoinKindPhantom.COLLECT_PROTOCOL_FEES]
	uint public dueProtocolFees;
	// The ID of the contract's Balancer pool, given to it when initialize() is called
	bytes32 private poolId;
	// Information for each token listed by the pool. Future versions of this contract should
	// consider storing more info here, as there is unused capacity in each 32-byte slot.
	// There is potential to store symbol, and decimal info in order to save gas.
	mapping(IERC20 => TokenInfo) private tokens;
	// Returns whether a given contract version has been initialized already
	mapping(uint16 => bool) private initialized;

	/// @notice Emitted when tokens are removed from the pool
	/// @param sender The transactor
	/// @param token The token removed
	event TokenRemove(address indexed sender, address indexed token);
	/// @notice Emitted when an ownership transfer has been initiated
	/// @param sender The transactor
	/// @param newOwner The address designated as the potential new owner
	event OwnerTransfer(address indexed sender, address newOwner);
	/// @notice Emitted when an ownership transfer is confirmed
	/// @param sender The transactor, and new owner
	/// @param oldOwner The old owner
	event OwnerConfirm(address indexed sender, address oldOwner);

	// This constructor is for compatibility's sake only, as the contract is designed to operate
	// behind a proxy, and the constructor will never be called in that environment
	constructor() BalancerPoolToken("UNSET", "UNSET", VAULT) {
		initialized[CONTRACT_VERSION] = true;
	}

	/// @notice Readies the contract for use, and registers it as a pool with Balancer.
	/// Must be called immediately after implementation in the proxy, as the contract's "owner"
	/// will be unset. Only needs to be called once per contract version.
	/// @param tokenName The name of the BPT, visible to users
	/// @param tokenSymbol The symbol (ticker) of the BPT, visible to users
	/// @dev This function must be entirely rewritten for subsequent contract versions, such that
	/// it only makes changes which are necessary for the new version to function. All variables
	/// will be retained between versions within the proxy contract.
	function initialize(
		string calldata tokenName,
		string calldata tokenSymbol
	) public {
		if (initialized[CONTRACT_VERSION]) _revert(Errors.INVALID_INITIALIZATION);
		Slot6 memory _slot6 = slot6;
		// Should never resolve to "true", but included for safety
		if (_slot6.owner != address(0))
			ExtraStorage.onlyOwner(_slot6.owner);
		_name = tokenName;
		_symbol = tokenSymbol;
		bytes32 _poolId = VAULT.registerPool(IVault.PoolSpecialization.GENERAL);
		poolId = _poolId;
		_slot6.owner = msg.sender;
		// Initiates the pool in its locked state
		_slot6.balanceFee = UINT8_MAX;
		balanceFeeCache = 10;
		tokens[this] = TokenInfo(TokenCategory.BASE, 1);
		tokens[SWD] = TokenInfo(TokenCategory.BASE, 1);
		_slot6.tokensLength += 2;
		IERC20[] memory _tokens = new IERC20[](2);
		_tokens[INDEX_BPT] = this;
		_tokens[INDEX_SWD] = SWD;
		VAULT.registerTokens(_poolId, _tokens, new address[](2));
		updateCachedProtocolSwapFeePercentage();
		slot6 = _slot6;
		initialized[CONTRACT_VERSION] = true;
	}

	/// @notice Adds tokens to the pool by address, but does not increase their balance.
	/// A token can only be added if it has a TokenPriceManager present in [ORACLE], which
	/// is a TokenPriceController. For details, see ITokenPriceManagerMinimal.sol, and
	/// ITokenPriceControllerDefault.sol. (Can only be called by the owner)
	/// @param _tokens A list of token addresses to add
	/// @param categories A list of [TokenCategory]s of the same length,
	/// and in the same order as [_tokens]
	/// @param weights A list of weights (uint8), of the same length and order as [_tokens], which
	/// dictates the respective token's weight within the chosen category
	function tokensAdd(
		IERC20[] calldata _tokens,
		TokenCategory[] calldata categories,
		uint8[] calldata weights
	) external {
		slot6 = ExtraStorage.tokensAddIterate(slot6, tokens, _tokens, categories, weights);
		VAULT.registerTokens(poolId, _tokens, new address[](_tokens.length));
	}

	/// @notice Removes tokens from the pool by address. Each token must have a zero balance within
	/// the pool before removal. One can achieve a zero balance by either buying all the tokens
	/// manually, or by incentivizing their sale by setting the token's weight to 0.
	/// (Can only be called by the owner)
	/// @param _tokens A list of token addresses to remove
	function tokensRemove(
		IERC20[] calldata _tokens
	) external {
		Slot6 memory _slot6 = slot6;
		ExtraStorage.onlyOwner(_slot6.owner);
		_require(_tokens.length < _slot6.tokensLength - 2, Errors.MIN_TOKENS);
		uint16[3] memory categoryWeights;
		for (uint i; i < _tokens.length; i++) {
			uint8 category = uint8(tokens[_tokens[i]].category);
			// The [category & 0x3 != 0] below detects that the token is both added,
			// and not in the [TokenCategory.BASE] category, using a binary trick
			_require(category & 0x3 != 0, Errors.INVALID_TOKEN);
			categoryWeights[category - 1] += tokens[_tokens[i]].inCategoryWeight;
			delete tokens[_tokens[i]];
			emit TokenRemove(_slot6.owner, address(_tokens[i]));
		}
		uint16[3] memory _inCategoryTotals =
			ExtraStorage.bytes6ToUint16Arr(_slot6.inCategoryTotals);
		for (uint i; i < categoryWeights.length; i++)
			_inCategoryTotals[i] -= categoryWeights[i];
		_slot6.inCategoryTotals = ExtraStorage.uint16ArrToBytes6(_inCategoryTotals);
		_slot6.tokensLength -= uint8(_tokens.length);
		VAULT.deregisterTokens(poolId, _tokens);
		slot6 = _slot6;
	}

	/// @notice Sets the balance fee to the requested value, which is used to incentivize traders
	/// into keeping the pool balanced according to the set weights.
	/// (Can only be called by the owner)
	/// @param fee The new fee (in tenths of a percent, ex. 10 = 1%)
	function setBalanceFee(uint8 fee) external {
		require(fee < UINT8_MAX, "NoMax");
		Slot6 memory _slot6 = slot6;
		ExtraStorage.onlyOwner(_slot6.owner);
		if (_slot6.balanceFee == UINT8_MAX)
			balanceFeeCache = fee;
		else
			_slot6.balanceFee = fee;
		slot6 = _slot6;
	}

	/// @notice Sets the weights for each category, relative to one-another:
	/// "products", "common", then "USD" (Can only be called by the owner).
	/// The sum of all three weights must be less than 256.
	/// See ICommonStructs.sol, or getSlot6() below for more details.
	/// @param weights Three weights (uint8) corresponding to each main category
	function setCategoryWeights(uint8[3] calldata weights) external {
		slot6 = ExtraStorage.setCategoryWeightsIterate(slot6, weights);
	}

	/// @notice Sets the weights for the requested tokens, relative to the other tokens
	/// in each token's category (Can only be called by the owner)
	/// @param _tokens A list of token addresses to modify (must already be added to the pool)
	/// @param weights A list of weights of the same length, and in the same order as [_tokens]
	function setTokenWeights(IERC20[] calldata _tokens, uint8[] calldata weights) external {
		_require(_tokens.length == weights.length, Errors.INPUT_LENGTH_MISMATCH);
		slot6 = ExtraStorage.setTokenWeightsIterate(slot6, _tokens, weights, tokens);
	}

	/// @notice Toggles the lock, which prevents swapping within the pool, and allows for exits.
	/// To unlock swaps, the pool must have some balance in a token besides the BPT, or SWD;
	/// and, by extension, the pool must have some BPT tokens circulating, outside the pool itself.
	/// Most useful for four things:
	/// 1) Locking the pool in case of an emergency/exploit.
	/// 2) Making 1-for-1 withdrawals by locking, exiting, and then unlocking the pool in one TX.
	///    This allows for the pool owner to withdraw without affecting the BPT, or SWD prices.
	/// 3) Decommissioning the pool.
	/// 4) Unlocking the pool after initialization.
	/// Call isLocked() to detect current lock state.
	/// (Can only be called by the owner)
	function toggleSwapLock() external {
		Slot6 memory _slot6 = slot6;
		ExtraStorage.onlyOwner(_slot6.owner);
		if (_slot6.balanceFee == UINT8_MAX) {
			(IERC20[] memory _tokens, uint[] memory balances,) =
				VAULT.getPoolTokens(poolId);
			ExtraStorage.toggleSwapLockCheckState(
				_tokens, balances,
				tokens, totalSupply(),
				dueProtocolFees
			);
			_slot6.balanceFee = balanceFeeCache;
			balanceFeeCache = 0;
		} else {
			balanceFeeCache = _slot6.balanceFee;
			_slot6.balanceFee = UINT8_MAX;
		}
		slot6 = _slot6;
	}

	/// @notice The standard "join" interface for Balancer pools, used in a nonstandard fashion.
	/// Cannot be called directly, but can be called through the vault's joinPool() function.
	/// Typical users do not call joinPool() to join, instead they should simply trade for the BPT
	/// token, as the BPTs are part of the (phantom) pool, like any other token.
	/// @dev Please see Balancer's IVault.sol for documentation on joinPool(), but do note:
	/// 1) The [JoinKindPhantom] is interpreted through the [userData] field, along with the
	///    requested [amountsIn].
	/// 2) maxAmountsIn[0] should always be type(uint).max, while the other values should match
	///    those passed in the userData field. This is to allow for mint/deposit combinations in
	///    certain join types, especially [JoinKindPhantom.INIT].
	function onJoinPool(
		bytes32 _poolId,
		address sender,
		address recipient,
		uint[] calldata balances,
		uint,
		uint,
		bytes calldata userData
	) external override returns (
		uint[] memory amountsIn,
		uint[] memory dueProtocolFeeAmounts
	) {
		onlyVault(_poolId);
		(JoinKindPhantom kind, uint[] memory amountsInRequested) = abi.decode(
			userData,
			(JoinKindPhantom, uint256[])
		);
		dueProtocolFeeAmounts = new uint[](balances.length);
		// Allows Balancer to collect fees due to their protocol
		if (kind == JoinKindPhantom.COLLECT_PROTOCOL_FEES) {
			amountsIn = new uint[](balances.length);
			dueProtocolFeeAmounts[INDEX_BPT] = dueProtocolFees;
			dueProtocolFees = 0;
		// Allows the pool owner to seed the pool with a balance after initialization
		} else if (kind == JoinKindPhantom.INIT && totalSupply() == 0) {
			_require(sender == recipient && recipient == slot6.owner, Errors.CALLER_IS_NOT_OWNER);
			amountsIn = amountsInRequested;
			uint initBPT;
			{
				(IERC20[] memory _tokens,,) = VAULT.getPoolTokens(poolId);
				(initBPT,,) = ExtraStorage.getValue(
					_tokens, amountsIn,
					INDEX_SWD, INDEX_SWD,
					totalSupply(), dueProtocolFees
				);
			}
			require(initBPT >= 10000 * EIGHTEEN_DECIMALS, "Min$20K");
			amountsIn[INDEX_BPT] = MAX_POOL_BPT;
			_mintPoolTokens(recipient, MAX_POOL_BPT + initBPT - (10 * EIGHTEEN_DECIMALS));
			_mintPoolTokens(address(0), (10 * EIGHTEEN_DECIMALS));
		// Allows anyone to "top-up" the BPT in the pool in case it runs low, and doing so has no
		// effect on the price of the BPT, or the value within the pool
		} else if (
			kind == JoinKindPhantom.TOP_UP_BPT &&
			balances[INDEX_BPT] < MAX_POOL_BPT
		) {
			amountsIn = new uint[](balances.length);
			uint amountBPT = MAX_POOL_BPT - balances[INDEX_BPT];
			amountsIn[INDEX_BPT] = amountBPT;
			_mintPoolTokens(recipient, amountBPT);
		} else {
			_revert(Errors.UNHANDLED_BY_PHANTOM_POOL);
		}
	}

	/// @notice The standard "exit" interface for Balancer pools, used in a nonstandard fashion.
	/// Cannot be called directly, but can be called through the vault's exitPool() function.
	/// Typical users do not call exitPool() to exit, instead they should simply trade the BPT for
	/// other tokens, as the BPTs are part of the (phantom) pool, like any other token.
	/// @dev Please see Balancer's IVault.sol for documentation on exitPool(), but do note:
	/// 1) The [ExitKindPhantom] is interpreted through the [userData] field, along with the
	///    requested [bptAmountIn].
	/// 2) minAmountsOut[0] should always be 0, as the zeroth token in the pool is always the BPT,
	///    and the pool will never return BPT upon exit. Other indexes can safely be set to 0 as
	///    well, given that the pool always returns in proportion to the BPT in circulation.
	function onExitPool(
		bytes32 _poolId,
		address sender,
		address,
		uint[] calldata balances,
		uint,
		uint,
		bytes calldata userData
	) external override returns (
		uint[] memory amountsOut,
		uint[] memory dueProtocolFeeAmounts
	) {
		onlyVault(_poolId);
		Slot6 memory _slot6 = slot6;
		ExtraStorage.onlyLocked(_slot6.balanceFee);
		(ExitKindPhantom kind, uint bptAmountIn) = abi.decode(
			userData,
			(ExitKindPhantom, uint256)
		);
		uint bptSupply = getCirculatingSupply(balances[INDEX_BPT]);
		_require(bptSupply >= bptAmountIn, Errors.ADDRESS_INSUFFICIENT_BALANCE);
		if (kind == ExitKindPhantom.EXACT_BPT_IN_FOR_TOKENS_OUT) {
			amountsOut = ExtraStorage.onExitPoolAmountsOut(balances, bptSupply, bptAmountIn);
			_burnPoolTokens(sender, bptAmountIn);
			dueProtocolFeeAmounts = new uint[](balances.length);
		} else {
			_revert(Errors.UNHANDLED_BY_PHANTOM_POOL);
		}
	}

	/// @notice The standard "swap" interface for Balancer pools. Cannot be called directly, but
	/// can be called through the vault's various swap functions. A "blocklock" is implemented to
	/// prevent flashloan attacks - although no attack vector is currently known.
	/// @dev Please see Balancer's IVault.sol for documentation on swaps.
	// Swap implementation is unique, and is composed internally using separate AMM methods:
	// 1) The first method applies to all tokens that are not the BPT, or SWD.
	//		• Tokens are bought and sold for the fair price dictated by the [ORACLE].
	//		• Buy versus sell price can be reported differently by the [ORACLE].
	//		• Tokens may run out entirely, and prices do not change according to balance
	//		  proportions (unlike Uniswap's constant-product method)
	//		• Tokens are maintained according to the set weights using a flat fee/bonus dictated by
	//		  the [slo6.balanceFee]. A user bringing the pool back into balance will receive a
	//		  bonus (reducing the BPT value), whereas a user bringing it out of balance will pay a
	//		  fee (increasing the BPT value). Balance is incentivized by offering rates different
	//		  from those in the wider market.
	//		• Fees due to the Balancer protocol are calculated by comparing the final output to a
	//		  hypothetical, feeless transaction.
	// 2) The second method applies to SWD.
	//		• SWD's price is calculated using the constant-product method (like Uniswap).
	//		• Rather than calculating against a single token (ex. WETH, USDC, etc.), SWD is 
	//		  compared to the entire sum of all other tokens in the pool (in USD).
	//		  With the BPT being "Token_0", and SWD being "Token_1":
	//
	//			Balance:		USD Sum:		Constant:
	//
	//							Token_2
	//			SWD		X		...			=	K
	//							Token_N
	//
	//		  Alternatively:
	//
	//			(SWD Price)×(SWD Balance) =
	//				(Token_2 Price)×(Token_2 Balance) + ... + (Token_N Price)×(Token_N Balance)
	//
	//		• Summing the USD value of all tokens can be gas-expensive, therefore future versions
	//		  of this contract should seek to make this process as efficient as possible, and care
	//		  should be taken when adding more tokens to the pool. A hard cap of 50 tokens has been
	//		  set within [ExtraStorage.MAX_TOKENS].
	// 3) The final method applies to the BPT.
	//		• Like SWD, the BPT's price is found through the summation of all value within the
	//		  pool, but rather than changing with balance proportions, the total pool value is
	//		  simply divided by the BPT's circulating supply.
	//
	//			USD Sum:		Balance:					USD Price:
	//
	//			Token_2
	//			...			/	(Circulating Supply)	=	BPT
	//			Token_N
	//
	//		• The BPT's circulating supply is found by subtracting the pool's balance from the
	//		  total supply, and then adding those tokens due as fees to the Balancer protocol, but
	//		  not yet issued.
	//
	//		  (Circulating Supply) = (Total Supply) - (Pool Balance) + (Due Protocol Fees)
	//
	//		• The process of the pool owner joining the pool with [JoinKindPhantom.INIT] mints the
	//		  initial supply of BPT, and deposits the initial balance within the pool. The total
	//		  balance remaining in the pool owner's wallet will equate 1-to-1 with every USD
	//		  (in value) deposited to the pool, excluding the value of the SWD. This gives the BPT
	//		  an initial value of $1.
	//		• As BPT are accounted for as they enter/leave the pool, the price of BPT will remain
	//		  constant for such transactions. The price of the BPT only changes if:
	//			1) The underlying tokens change in value.
	//			2) Trades are made with the SWD balance (thus changing SWD's value).
	//			3) The pool accumulates fees, or grants trade bonuses.
	//		  This makes the BPT's performance as an asset easy to understand for the end user.
	//		• Intuitively, one might expect that the BPT should be valued using double the pool's
	//		  total value, in order to account for the value of the pool's SWD. However, this would
	//		  be an error, as shown in the following scenario.
	//		  	1) A user owns all circulating BPT.
	//			2) That user sells half their BPT to purchase all tokens except the SWD.
	//			3) The user then sells zero BPT to purchase all the SWD which are now worth nothing.
	//			4) The user retains half their original BPT, while the pool is now empty.
	//		  Accounting for the BPT's price properly avoids such a possibility.
	// All complexity is abstracted away from the end user, and these solutions are compatible with
	// DEx aggregators. Trades from SWD to the BPT are not allowed directly, acting as an
	// artificial bias towards SWD's positive price-action.
	function onSwap(
		SwapRequest calldata swapRequest,
		uint[] calldata balances,
		uint indexIn,
		uint indexOut
	) external override returns (uint amount) {
		_require(balances[indexOut] != 0, Errors.INSUFFICIENT_BALANCE);
		if (
			indexIn == INDEX_SWD &&
			indexOut == INDEX_BPT
		) {
			_revert(Errors.UNHANDLED_JOIN_KIND);
		}
		onlyVault(swapRequest.poolId);
		require(swapRequest.lastChangeBlock != block.number, "BlockLock");
		Slot6 memory _slot6 = slot6;
		ExtraStorage.notLocked(_slot6.balanceFee);
		GetValue memory _getValue;
		TokenData memory _tokenData;
		{
			(IERC20[] memory _tokens,,) = VAULT.getPoolTokens(poolId);
			(_getValue.totalMinusSWD, _getValue.indexIn,
			_getValue.indexOut) = ExtraStorage.getValue(
				_tokens, balances,
				indexIn, indexOut,
				totalSupply(), dueProtocolFees
			);
			_getValue.bpt = ExtraStorage.safeMul(
				_getValue.totalMinusSWD,
				EIGHTEEN_DECIMALS
			) / getCirculatingSupply(balances[INDEX_BPT]);
			_tokenData.indexIn = indexIn;
			_tokenData.indexOut = indexOut;
			_tokenData.inInfo = tokens[swapRequest.tokenIn];
			_tokenData.outInfo = tokens[swapRequest.tokenOut];
		}
		IndexPricing memory _pricing;
		_pricing.indexIn = (_tokenData.inInfo.category == TokenCategory.BASE) ?
			ExtraStorage.onSwapGetIndexInPricing(
				swapRequest, balances,
				_getValue, _tokenData
			) :
			ExtraStorage.onSwapGetComplexPricing(
				_getValue.totalMinusSWD,
				swapRequest.tokenIn,
				_tokenData.inInfo,
				_getValue.indexIn,
				_slot6,
				true
			);
		_pricing.indexOut = (_tokenData.outInfo.category == TokenCategory.BASE) ?
			ExtraStorage.onSwapGetIndexOutPricing(
				swapRequest, balances,
				_getValue, _tokenData
			) :
			ExtraStorage.onSwapGetComplexPricing(
				_getValue.totalMinusSWD,
				swapRequest.tokenOut,
				_tokenData.outInfo,
				_getValue.indexOut,
				_slot6,
				false
			);
		amount = ExtraStorage.onSwapGetAmount(swapRequest, balances, _tokenData, _pricing);
		dueProtocolFees += ExtraStorage.onSwapCalculateFees(
			swapRequest, _getValue, _tokenData, _pricing,
			amount, cachedProtocolSwapFeePercentage
		);
	}

	/// @notice Initiates an ownership transfer, but the new owner must call ownerConfirm()
	/// within 36 hours to finalize (Can only be called by the owner)
	/// @param _ownerNew The new owner's address
	function ownerTransfer(address _ownerNew) external {
		ExtraStorage.onlyOwner(slot6.owner);
		ownerNew = _ownerNew;
		ownerTransferTimeout = block.timestamp + 36 hours;
		emit OwnerTransfer(msg.sender, _ownerNew);
	}

	/// @notice Finalizes an ownership transfer (Can only be called by the new owner)
	function ownerConfirm() external {
		ExtraStorage.onlyOwner(ownerNew);
		if (block.timestamp > ownerTransferTimeout) _revert(Errors.EXPIRED_PERMIT);
		address _ownerOld = slot6.owner;
		slot6.owner = ownerNew;
		ownerNew = address(0);
		ownerTransferTimeout = 0;
		emit OwnerConfirm(msg.sender, _ownerOld);
	}

	/// @notice Used to rescue mis-sent tokens from the contract address
	/// (Can only be called by the contract owner)
	/// @param _token The address of the token to be rescued
	function withdrawToken(address _token) external {
		address _owner = slot6.owner;
		ExtraStorage.onlyOwner(_owner);
		_require(IERC20(_token).transfer(
				_owner,
				IERC20(_token).balanceOf(address(this))
			),
			Errors.SAFE_ERC20_CALL_FAILED
		);
	}

	/// @notice Updates the Balancer protocol's swap fee (Can be called by anyone)
	function updateCachedProtocolSwapFeePercentage() public {
		cachedProtocolSwapFeePercentage = VAULT.getProtocolFeesCollector().getSwapFeePercentage();
	}

	/// @notice Gets pricing information for both the BPT, and SWD
	/// @return bptValue The BPT's current price (in USD with 18-decimals of precision)
	/// @return swdValue SWD's current price (in USD with 18-decimals of precision)
	function getValue() external view returns (uint bptValue, uint swdValue) {
		TokenValuation memory bptTotal;
		TokenValuation memory swdTotal;
		{
			(IERC20[] memory _tokens, uint[] memory balances,) =
				VAULT.getPoolTokens(poolId);
			(,bptTotal,swdTotal) = ExtraStorage.getValue(
				_tokens, balances,
				INDEX_BPT, INDEX_SWD,
				totalSupply(), dueProtocolFees
			);
		}
		return (bptTotal.price, swdTotal.price);
	}

	/// @notice Gets the current state of the "swap lock" which prevents swaps within the pool
	/// @return bool "True" indicates that the pool is locked, "false" indicates that it's unlocked.
	function isLocked() external view returns (bool) {
		return (slot6.balanceFee == UINT8_MAX);
	}

	/// @notice Gets the BPT's current circulating supply
	/// @return uint The BPT's circulating supply
	function getCirculatingSupply() external view returns (uint) {
		(,uint[] memory balances,) = VAULT.getPoolTokens(poolId);
		return getCirculatingSupply(balances[INDEX_BPT]);
	}

	/// @notice Standard Balancer interface for getting the pool's internal ID
	///	@return bytes32 The pool's ID, given to it by Balancer upon registration
	function getPoolId() external view override returns (bytes32) { return poolId; }

	/// @notice Helper function for reading the [slot6] struct
	/// @dev [slot6] uses fixed-size byte arrays for [categoryWeights], and [inCategoryTotals] in
	/// order to achieve tighter packing, and to stay within a single 32-byte slot; however, these
	/// variables are used internally as fixed-size uint8/uint16 arrays. This function grants the
	/// end user an easier method for reading these values on/off-chain.
	/// Please see ICommonStructs.sol for further documentation.
	/// @return owner The current contract owner
	/// @return tokensLength The number of tokens managed by the pool, including the BPT, and SWD
	/// @return balanceFee The current, flat fee used to maintain the token balances according to
	/// the configured weights, expressed in tenths of a percent (ex. 10 = 1%). Can also be set to
	/// 255 (type(uint8).max) to indicate that the "swap lock" is engaged, in which case the
	/// balance fee can be found in [balanceFeeCache].
	/// @return categoryWeights The weights of the three, primary categories (DAO Products, Common
	/// Tokens, and USD-related tokens) relative to one another (ex. [1, 1, 1] would grant 1/3 of
	/// the pool to each category)
	/// @return categoryWeightsTotal The sum of all [categoryWeights]
	/// @return inCategoryTotals The sum of all individual, token wights within a given category
	function getSlot6() external view returns (
		address owner, uint8 tokensLength, uint8 balanceFee,
		uint8[3] memory categoryWeights, uint8 categoryWeightsTotal,
		uint16[3] memory inCategoryTotals
	) {
		Slot6 memory _slot6 = slot6;
		categoryWeights[0] = uint8(_slot6.categoryWeights[0]);
		categoryWeights[1] = uint8(_slot6.categoryWeights[1]);
		categoryWeights[2] = uint8(_slot6.categoryWeights[2]);
		return (
			_slot6.owner, _slot6.tokensLength, _slot6.balanceFee,
			categoryWeights, _slot6.categoryWeightsTotal,
			ExtraStorage.bytes6ToUint16Arr(_slot6.inCategoryTotals)
		);
	}

	/// @notice Returns a fake "swap fee" for compliance with standard Balancer interfaces
	/// @return uint256 A falsified "swap fee", set to the minimum allowed by Balancer. Actual swap
	/// fee varies depending on the tokens traded. Due protocol fees are properly accounted for
	/// during swaps, are stored in [dueProtocolFees], and can be claimed through a joinPool()
	/// using [JoinKindPhantom.COLLECT_PROTOCOL_FEES].
	function getSwapFeePercentage() external pure returns (uint256) {
		return SWAP_FEE_PERCENTAGE;
	}

	/// @notice Returns the internal version of this contract, which is mainly used to maintain
	/// consistency within the proxy.
	/// @return uint16 The version number, with 2-decimals of precision (ex. 100 = 1.00).
	function getVersion() external pure returns (uint16) {
		return CONTRACT_VERSION;
	}

	/// @notice Returns the internal version of the [ExtraStorage] library, along with its address
	/// @return uint16 The version number, with 2-decimals of precision (ex. 100 = 1.00).
	/// @return address The address of the [ExtraStorage] library.
	function getVersionStorage() external pure returns (uint16, address) {
		return (ExtraStorage.CONTRACT_VERSION, address(ExtraStorage));
	}

	// Internal version of getCirculatingSupply() useful for memory management
	function getCirculatingSupply(uint bptBalance) private view returns (uint bptAmount) {
		return totalSupply() - bptBalance + dueProtocolFees;
	}

	// Reverts if the [msg.sender] is not the [VAULT]
	function onlyVault(bytes32 _poolId) private view {
		_require(
			msg.sender == address(VAULT) &&
			_poolId == poolId, Errors.CALLER_NOT_VAULT
		);
	}
}