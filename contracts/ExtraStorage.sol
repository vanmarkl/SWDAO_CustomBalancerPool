// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ITokenPriceControllerDefault} from
	"token-price-manager/src/interfaces/ITokenPriceControllerDefault.sol";
import {ITokenPriceManagerMinimal} from
	"token-price-manager/src/interfaces/ITokenPriceManagerMinimal.sol";
import {IPoolSwapStructs} from "@balancer-labs/v2-vault/contracts/interfaces/IPoolSwapStructs.sol";
import "@balancer-labs/v2-vault/contracts/interfaces/IVault.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol";

import "./ICommonStructs.sol";

/// @title Extra Storage for the SW DAO Balancer pool
/// @author Peter T. Flynn
/// @notice Useful for staying within the EVM's limit for contract bytecode
/// @dev Later versions of the [CustomBalancerPool] contract should do away with this library in
/// favor of having each function stored in their own contracts, with a local singleton for onSwap.
/// This current library-based implementation is not gas-efficient, and was done as a concession
/// for the time-sensitive nature of this project.
library ExtraStorage {
	ITokenPriceControllerDefault constant ORACLE =
		ITokenPriceControllerDefault(0x8A46Eb6d66100138A5111b803189B770F5E5dF9a);

	// Always known, set at the first run of initialize()
	uint constant INDEX_BPT = 0;
	// Always known, set at the first run of initialize()
	uint constant INDEX_SWD = 1;
	// Named for readability
	uint8 constant UINT8_MAX = type(uint8).max;
	// Useful in common, fixed-point math - named for readability
	uint constant EIGHTEEN_DECIMALS = 1e18;
	// Sets a hard cap on the number of tokens that the pool may manage.
	// Attempting to add more reverts with [Errors.MAX_TOKENS] (BAL#201).
	uint8 constant MAX_TOKENS = 50;

	// Must be incremented whenever a new library implementation is deployed
	uint16 constant CONTRACT_VERSION = 100; // Version 1.00;

	/// @notice Emitted when tokens are added to the pool
	/// @param sender The transactor
	/// @param token The token added
	/// @param category The token's category
	/// @param weight The token's weight within that category
	event TokenAdd(
		address indexed sender,
		address indexed token,
		ICommonStructs.TokenCategory indexed category,
		uint8 weight
	);

	// Adds tokens to be managed by the pool
	// Checks that each token:
	// 1) Doesn't already exist in the pool
	// 2) Doesn't put the pool over the [MAX_TOKENS] limit
	// 3) Has a price provider in [ORACLE]
	// 4) Is being added to a valid category
	function tokensAddIterate(
		ICommonStructs.Slot6 memory _slot6,
		mapping(IERC20 => ICommonStructs.TokenInfo) storage tokens,
		IERC20[] calldata _tokens,
		ICommonStructs.TokenCategory[] calldata categories,
		uint8[] calldata weights
	) public returns (ICommonStructs.Slot6 memory) {
		onlyOwner(_slot6.owner);
		_require(
			_slot6.tokensLength + _tokens.length <= MAX_TOKENS,
			Errors.MAX_TOKENS
		);
		_require(
			_tokens.length == categories.length &&
			_tokens.length == weights.length,
			Errors.INPUT_LENGTH_MISMATCH
		);
		uint16[3] memory categoryWeights;
		for (uint i; i < _tokens.length; i++) {
			_require(
				tokens[_tokens[i]].category == ICommonStructs.TokenCategory.NULL,
				Errors.TOKEN_ALREADY_REGISTERED
			);
			_require(isContract(_tokens[i]), Errors.INVALID_TOKEN);
			address oracleReportedAddress = ORACLE
				.getManager(
					ERC20(address(_tokens[i])).symbol()
				).getTokenPrimary();
			_require(
				address(_tokens[i]) == oracleReportedAddress,
				Errors.TOKEN_DOES_NOT_HAVE_RATE_PROVIDER
			);
			getValue(
				_tokens[i],
				ITokenPriceManagerMinimal.PriceType.RAW
			);
			uint8 category = uint8(categories[i]);
			// The [category & 0x3 != 0] below detects that the token is both added,
			// and not in the [TokenCategory.BASE] category, using a binary trick
			_require(category & 0x3 != 0, Errors.INVALID_TOKEN);
			categoryWeights[category - 1] += weights[i];
			tokens[_tokens[i]] = ICommonStructs.TokenInfo(categories[i], weights[i]);
			emit TokenAdd(_slot6.owner, address(_tokens[i]), categories[i], weights[i]);
		}
		uint16[3] memory _inCategoryTotals =
			bytes6ToUint16Arr(_slot6.inCategoryTotals);
		for (uint i; i < categoryWeights.length; i++)
			_inCategoryTotals[i] += categoryWeights[i];
		_slot6.inCategoryTotals = uint16ArrToBytes6(_inCategoryTotals);
		_slot6.tokensLength += uint8(_tokens.length);
		return _slot6;
	}

	// Sets the weights for the three, primary categories, as explained above the parent function
	function setCategoryWeightsIterate(
		ICommonStructs.Slot6 memory _slot6,
		uint8[3] calldata weights
	) public view returns (ICommonStructs.Slot6 memory) {
		onlyOwner(_slot6.owner);
		uint16 total = uint16(weights[0]) + uint16(weights[1]) + uint16(weights[2]);
		_slot6.categoryWeights = bytes3(
			bytes1(weights[0]) |
			bytes2(bytes1(weights[1])) >> 8 |
			bytes3(bytes1(weights[2])) >> 16
		);
		_require(total <= UINT8_MAX, Errors.ADD_OVERFLOW);
		_slot6.categoryWeightsTotal = uint8(total);
		return _slot6;
	}

	// Sets the weights of the requested tokens, as explained above the parent function.
	// Checks that each token:
	// 1) Exists in the pool
	// 2) Is in a category where weight changes are allowed
	function setTokenWeightsIterate(
		ICommonStructs.Slot6 memory _slot6,
		IERC20[] calldata _tokens,
		uint8[] calldata weights,
		mapping(IERC20 => ICommonStructs.TokenInfo) storage tokens
	) public returns (ICommonStructs.Slot6 memory) {
		onlyOwner(_slot6.owner);
		for (uint i; i < _tokens.length; i++) {
			ICommonStructs.TokenInfo memory tokenInfo = tokens[_tokens[i]];
			uint8 categoryIndex = uint8(tokenInfo.category) - 1;
			// The [uint8(tokenInfo.category) & 0x3 != 0] below detects that the token is both
			// added, and not in the [TokenCategory.BASE] category, using a binary trick
			_require(uint8(tokenInfo.category) & 0x3 != 0, Errors.INVALID_TOKEN);
			uint16[3] memory _inCategoryTotals =
				bytes6ToUint16Arr(_slot6.inCategoryTotals);
			_inCategoryTotals[categoryIndex] = 
				_inCategoryTotals[categoryIndex] - tokenInfo.inCategoryWeight + weights[i];
			_slot6.inCategoryTotals = uint16ArrToBytes6(_inCategoryTotals);
			tokenInfo.inCategoryWeight = weights[i];
			tokens[_tokens[i]] = tokenInfo;
		}
		return _slot6;
	}

	// Checks to ensure that the pool can be unlocked, as explained above the parent function
	function toggleSwapLockCheckState(
		IERC20[] calldata _tokens,
		uint[] calldata balances,
		mapping(IERC20 => ICommonStructs.TokenInfo) storage tokens,
		uint totalSupply,
		uint dueProtocolFees
	) public view {
		_require(
			(totalSupply - balances[INDEX_BPT] + dueProtocolFees) > 0,
			Errors.UNINITIALIZED
		);
		_require(_tokens.length > 2, Errors.UNINITIALIZED);
		bool someBalance;
		for (uint i; i < _tokens.length; i++) {
			if (i == INDEX_BPT)
				continue;
			ICommonStructs.TokenInfo memory tokenInfo = tokens[_tokens[i]];
			if (tokenInfo.inCategoryWeight > 0 && balances[i] > 0) {
				if (i != INDEX_SWD)
					someBalance = true;
			} else if (i == INDEX_SWD) {
				_revert(Errors.UNINITIALIZED);
			}
		}
		_require(someBalance, Errors.UNINITIALIZED);
	}

	// Returns token amounts in proportion to the total BPT in circulation, as explained above the
	// parent function
	function onExitPoolAmountsOut(
		uint[] calldata balances,
		uint bptSupply,
		uint bptAmountIn
	) public pure returns (uint[] memory amountsOut) {
		amountsOut = new uint[](balances.length);
		if (bptAmountIn == 0)
			return amountsOut;
		for (uint i = 1; i < balances.length; i++) {
			if	(balances[i] == 0)
				continue;
			amountsOut[i] = safeMul(
				balances[i],
				bptAmountIn
			) / bptSupply;
		}
	}

	// Gathers pricing information for the case in which the user is trading either the BPT, or SWD
	// for some other token. See [ICommonStructs.sol -> struct ComplexPricing] for details.
	// Implements a constant-product pricing style for SWD.
	function onSwapGetIndexInPricing(
		IPoolSwapStructs.SwapRequest calldata swapRequest,
		uint[] calldata balances,
		ICommonStructs.GetValue calldata _getValue,
		ICommonStructs.TokenData calldata _tokenData
	) public pure returns (ICommonStructs.ComplexPricing[3] memory indexInPricing) {
		if (_tokenData.indexIn == INDEX_BPT) {
			indexInPricing[0].price = _getValue.bpt;
		} else if (_tokenData.indexIn == INDEX_SWD) {
			if (swapRequest.kind == IVault.SwapKind.GIVEN_IN) {
				uint workingValue = safeMul(
					_getValue.totalMinusSWD,
					swapRequest.amount
				) / (balances[INDEX_SWD] + swapRequest.amount);
				indexInPricing[0].price = safeMul(
					workingValue,
					EIGHTEEN_DECIMALS
				) / swapRequest.amount;
			} else {
				uint buyValue = safeMul(
					_getValue.indexOut.price,
					swapRequest.amount
				) / EIGHTEEN_DECIMALS;
				uint workingValue = safeMul(
					balances[INDEX_SWD],
					buyValue
				) / (_getValue.totalMinusSWD - buyValue);
				indexInPricing[0].price = safeMul(
					buyValue,
					EIGHTEEN_DECIMALS
				) / workingValue;
			}
		}
	}

	// Gathers pricing information for the case in which the user is trading some token for either
	// the BPT, or SWD. See [ICommonStructs.sol -> struct ComplexPricing] for details.
	// Implements a constant-product pricing style for SWD.
	function onSwapGetIndexOutPricing(
		IPoolSwapStructs.SwapRequest calldata swapRequest,
		uint[] calldata balances,
		ICommonStructs.GetValue calldata _getValue,
		ICommonStructs.TokenData calldata _tokenData
	) public pure returns (ICommonStructs.ComplexPricing[3] memory indexOutPricing) {
		if (_tokenData.indexOut == INDEX_BPT) {
			indexOutPricing[0].price = _getValue.bpt;
		} else if (_tokenData.indexOut == INDEX_SWD) {
			if (swapRequest.kind == IVault.SwapKind.GIVEN_IN) {
				uint workingValue = (_tokenData.indexIn == INDEX_BPT) ?
					_getValue.bpt :
					_getValue.indexIn.price;
				uint buyValue = safeMul(
					workingValue,
					swapRequest.amount
				) / EIGHTEEN_DECIMALS;
				workingValue = safeMul(
					balances[INDEX_SWD],
					buyValue
				) / (_getValue.totalMinusSWD + buyValue);
				indexOutPricing[0].price = safeMul(
					buyValue,
					EIGHTEEN_DECIMALS
				) / workingValue;
			} else {
				uint workingValue = safeMul(
					_getValue.totalMinusSWD,
					swapRequest.amount
				) / (balances[INDEX_SWD] - swapRequest.amount);
				indexOutPricing[0].price = safeMul(
					workingValue,
					EIGHTEEN_DECIMALS
				) / swapRequest.amount;
			}
		}
	}

	// Gathers pricing information for the case in which the user is trading a token besides the
	// BPT, or SWD (irrespective of whether BPT/SWD is on the opposite side of the trade).
	// Pricing is handled in three tiers according to its balance within the pool:
	// 1) The token is below its configured weight (incentive for user to buy).
	// 2) The token is above its configured weight (incentive for user to sell).
	// 3) The token is within 2% of its configured weight (no incentive).
	// A user may pass through multiple tiers during a single trade.
	// See [ICommonStructs.sol -> struct ComplexPricing] for further details.
	function onSwapGetComplexPricing(
		uint totalMinusSWDValue,
		IERC20 token,
		ICommonStructs.TokenInfo calldata tokenInfo,
		ICommonStructs.TokenValuation memory tokenValue,
		ICommonStructs.Slot6 calldata _slot6,
		bool buySell
	) public view returns (ICommonStructs.ComplexPricing[3] memory pricing) {
		uint16[3] memory inCategoryTotals = bytes6ToUint16Arr(_slot6.inCategoryTotals);
		uint totalTarget = safeMul(
			(	safeMul(
					totalMinusSWDValue,
					uint8(_slot6.categoryWeights[uint8(tokenInfo.category) - 1])
				) / _slot6.categoryWeightsTotal
			),
			tokenInfo.inCategoryWeight
		) / inCategoryTotals[uint8(tokenInfo.category) - 1];
		uint totalMargin = (safeMul(totalTarget, 51) / 50) - totalTarget;
		if (tokenValue.total == 0) tokenValue.total++;
		for (uint i; tokenValue.total > 0; i++) {
			if (tokenValue.total > totalTarget + totalMargin) {
				if (buySell) {
					pricing[i].price = safeMul(
						getValue(
							token,
							ITokenPriceManagerMinimal.PriceType.SELL
						),
						1000 - _slot6.balanceFee
					) / 1000;
					tokenValue.total = 0;
				} else {
					pricing[i].price = safeMul(
						tokenValue.price,
						1000 - _slot6.balanceFee
					) / 1000;
					pricing[i].amount = safeMul(
						tokenValue.total - totalTarget - totalMargin,
						EIGHTEEN_DECIMALS
					) / tokenValue.price;
					tokenValue.total = totalTarget + totalMargin;
				}
			} else if (tokenValue.total < totalTarget - totalMargin) {
				if (buySell) {
					pricing[i].price = safeMul(
						tokenValue.price,
						1000 + _slot6.balanceFee
					) / 1000;
					pricing[i].amount = safeMul(
						totalTarget - totalMargin - tokenValue.total,
						EIGHTEEN_DECIMALS
					) / tokenValue.price;
					tokenValue.total = totalTarget - totalMargin;
				} else {
					pricing[i].price = safeMul(
						getValue(
							token,
							ITokenPriceManagerMinimal.PriceType.BUY
						),
						1000 + _slot6.balanceFee
					) / 1000;
					tokenValue.total = 0;
				}
			} else {
				if (buySell) {
					pricing[i].price = getValue(
						token,
						ITokenPriceManagerMinimal.PriceType.SELL
					);
					pricing[i].amount = safeMul(
						totalTarget + totalMargin - tokenValue.total + 1,
						EIGHTEEN_DECIMALS
					) / tokenValue.price;
					tokenValue.total = totalTarget + totalMargin + 1;
				} else {
					pricing[i].price = getValue(
						token,
						ITokenPriceManagerMinimal.PriceType.BUY
					);
					pricing[i].amount = safeMul(
						tokenValue.total - totalTarget + totalMargin - 1,
						EIGHTEEN_DECIMALS
					) / tokenValue.price;
					tokenValue.total = totalTarget - totalMargin - 1;
				}
			}
		}
	}

	// Utilized in onSwapGetAmount() to convert two sets of [ComplexPricing] data into an
	// [outAmount] that onSwapGetAmount() can further process.
	// See [ICommonStructs.sol -> struct ComplexPricing] for further details.
	function onSwapCalculateTrade(
		ICommonStructs.ComplexPricing[3] calldata inPricing,
		ICommonStructs.ComplexPricing[3] calldata outPricing,
		uint inAmount
	) public pure returns (uint outAmount) {
		uint inValueTotal;
		for (uint i; inAmount > 0; i++) {
			if (inAmount < inPricing[i].amount || inPricing[i].amount == 0) {
				inValueTotal += safeMul(
					inAmount,
					inPricing[i].price
				) / EIGHTEEN_DECIMALS;
				inAmount = 0;
			} else {
				inValueTotal += safeMul(
					inPricing[i].amount,
					inPricing[i].price
				) / EIGHTEEN_DECIMALS;
				inAmount -= inPricing[i].amount;
			} 
		}
		for (uint i; inValueTotal > 0; i++) {
			uint stepTotal = (outPricing[i].amount == 0) ?
				0 :
				safeMul(
					outPricing[i].amount,
					outPricing[i].price
				) / EIGHTEEN_DECIMALS;
			if (inValueTotal < stepTotal || outPricing[i].amount == 0) {
				outAmount += safeMul(
					inValueTotal,
					EIGHTEEN_DECIMALS
				) / outPricing[i].price;
				inValueTotal = 0;
			} else {
				inValueTotal -= stepTotal;
				outAmount += outPricing[i].amount;
			}
		}
	}

	// Constructs a final amount for onSwap() to return to the [VAULT], utilizing
	// onSwapCalculateTrade() above. Checks to ensure the pool has enough balance in the requested
	// token to settle the trade. Handles the differences between Balancer's
	// [IVault.SwapKind.GIVEN_IN] versus [IVault.SwapKind.GIVEN_OUT].
	function onSwapGetAmount(
		IPoolSwapStructs.SwapRequest calldata swapRequest,
		uint[] calldata balances,
		ICommonStructs.TokenData calldata _tokenData,
		ICommonStructs.IndexPricing calldata _pricing
	) public view returns (uint amount) {
		if (swapRequest.kind == IVault.SwapKind.GIVEN_IN) {
			amount = onSwapCalculateTrade(
				_pricing.indexIn,
				_pricing.indexOut,
				safeMul(
					swapRequest.amount, 
					10 ** (18 - ERC20(address(swapRequest.tokenIn)).decimals())
				)
			) / 10 ** (18 - ERC20(address(swapRequest.tokenOut)).decimals());
			if (amount > balances[_tokenData.indexOut])
				amount = balances[_tokenData.indexOut];
		} else {
			_require(
				swapRequest.amount <= balances[_tokenData.indexOut],
				Errors.INSUFFICIENT_BALANCE
			);
			amount = onSwapCalculateTrade(
				_pricing.indexOut,
				_pricing.indexIn,
				safeMul(
					swapRequest.amount, 
					10 ** (18 - ERC20(address(swapRequest.tokenOut)).decimals())
				)
			) / 10 ** (18 - ERC20(address(swapRequest.tokenIn)).decimals());
		}
	}

	// Constructs a hypothetical, feeless transaction to which the amount returned by
	// onSwapGetAmount() is compared. If the feeless transaction results in a better trade for the
	// user, the difference between the two amounts is taken, and that difference is used to
	// calculate the "swap fee". That "swap fee" allows us to calculate fees due to the Balancer
	// protocol, according to Balancer governance' requested fee percent. Fees are paid in the BPT.
	// Note: trades that involve the BPT are excluded from fee calculations (sorry Balancer), this	
	// is due to the fact that this contract currently can't deal with negative fees. This may
	// change in future versions.
	function onSwapCalculateFees(
		IPoolSwapStructs.SwapRequest calldata swapRequest,
		ICommonStructs.GetValue memory _getValue,
		ICommonStructs.TokenData calldata _tokenData,
		ICommonStructs.IndexPricing calldata _pricing,
		uint amount,
		uint cachedProtocolSwapFeePercentage
	) public view returns (uint) {
		if (
			!(
				_tokenData.indexIn == INDEX_BPT ||
				_tokenData.indexOut == INDEX_BPT
			)
		) {
			if (_tokenData.indexIn == INDEX_SWD)
				_getValue.indexIn.price = _pricing.indexIn[0].price;
			if (_tokenData.indexOut == INDEX_SWD)
				_getValue.indexOut.price = _pricing.indexOut[0].price;
			if (swapRequest.kind == IVault.SwapKind.GIVEN_IN) {
				uint rawAmount = safeMul(
					_getValue.indexIn.price,
					safeMul(
						swapRequest.amount,
						10 ** (18 - ERC20(address(swapRequest.tokenIn)).decimals())
					)
				) / _getValue.indexOut.price;
				amount = safeMul(
					amount,
					10 ** (18 - ERC20(address(swapRequest.tokenOut)).decimals())
				);
				if (rawAmount > amount) {
					return safeMul(
						(	safeMul(
								rawAmount - amount,
								_getValue.indexOut.price
							) / EIGHTEEN_DECIMALS
						),
						cachedProtocolSwapFeePercentage
					) / (_getValue.bpt * 100);
				}
			} else {
				uint rawAmount = safeMul(
					_getValue.indexOut.price,
					safeMul(
						swapRequest.amount,
						10 ** (18 - ERC20(address(swapRequest.tokenOut)).decimals())
					)
				) / _getValue.indexIn.price;
				amount = safeMul(
					amount,
					10 ** (18 - ERC20(address(swapRequest.tokenIn)).decimals())
				);
				if (rawAmount < amount) {
					return safeMul(
						(	safeMul(
								amount - rawAmount,
								_getValue.indexIn.price
							) / EIGHTEEN_DECIMALS
						),
						cachedProtocolSwapFeePercentage
					) / (_getValue.bpt * 100);
				}
			}
		}
		return 0;
	}

	// Gets the price of a token, with the requested [ITokenPriceManagerMinimal.PriceType],
	// from the [ORACLE] (in USD, with 18-decimals of precision)
	function getValue(
		IERC20 token,
		ITokenPriceManagerMinimal.PriceType priceType
	) public view returns (uint usdValue) {
		address denominator;
		(usdValue, denominator) = ORACLE
			.getManager(
				ERC20(address(token)).symbol()
			).getPrice(priceType);
		if (denominator != address(0))
			usdValue = ExtraStorage.safeMul(
				usdValue,
				getValue(IERC20(denominator), ITokenPriceManagerMinimal.PriceType.RAW)
			) / EIGHTEEN_DECIMALS;
		_require(usdValue != 0, Errors.TOKEN_DOES_NOT_HAVE_RATE_PROVIDER);
	}

	// Given an [indexIn]/[indexOut], among other information, this function returns returns five
	// points of data:
	// 1) The total USD value of all assets managed by the pool, excluding the BPT, and SWD.
	// 2) The price of an [indexIn] token in USD.
	// 3) The USD value of all [indexIn] tokens managed by the pool.
	// 2) The price of an [indexOut] token in USD.
	// 3) The USD value of all [indexOut] tokens managed by the pool.
	function getValue(
		IERC20[] calldata _tokens,
		uint[] calldata balances,
		uint indexIn,
		uint indexOut,
		uint totalSupply,
		uint dueProtocolFees
	) public view returns (
		uint totalMinusSWDValue,
		ICommonStructs.TokenValuation memory indexInValue,
		ICommonStructs.TokenValuation memory indexOutValue
	) {
		_require(
			_tokens.length == balances.length,
			Errors.INPUT_LENGTH_MISMATCH
		);
		for (uint i; i < _tokens.length; i++) {
			if (i == INDEX_BPT || i == INDEX_SWD)
				continue;
			uint value = getValue(_tokens[i], ITokenPriceManagerMinimal.PriceType.RAW);
			uint totalValue = ExtraStorage.safeMul(value, balances[i]) /
				(10 ** ERC20(address(_tokens[i])).decimals());
			totalMinusSWDValue += totalValue;
			if (i == indexIn) {
				indexInValue.total = totalValue;
				indexInValue.price = value;
			} else if (i == indexOut) {
				indexOutValue.total = totalValue;
				indexOutValue.price = value;
			}
		}
		if (indexIn == INDEX_BPT) {
			indexInValue.total = totalMinusSWDValue;
			indexInValue.price = ExtraStorage.safeMul(
				indexInValue.total,
				EIGHTEEN_DECIMALS
			) / (totalSupply - balances[INDEX_BPT] + dueProtocolFees);
		} else if (indexIn == INDEX_SWD) {
			indexInValue.total = totalMinusSWDValue;
			indexInValue.price = ExtraStorage.safeMul(
				indexInValue.total,
				EIGHTEEN_DECIMALS
			) / balances[INDEX_SWD];
		}
		if (indexOut == INDEX_BPT) {
			indexOutValue.total = totalMinusSWDValue;
			indexOutValue.price = ExtraStorage.safeMul(
				indexOutValue.total,
				EIGHTEEN_DECIMALS
			) / (totalSupply - balances[INDEX_BPT] + dueProtocolFees);
		} else if (indexOut == INDEX_SWD) {
			indexOutValue.total = totalMinusSWDValue;
			indexOutValue.price = ExtraStorage.safeMul(
				indexOutValue.total,
				EIGHTEEN_DECIMALS
			) / balances[INDEX_SWD];
		}
	}

	// Reverts if [msg.sender] is not the specified owner. Not made a modifier in order to work well
	// with the gas-saving [slot6].
	function onlyOwner(address _owner) internal view {
		_require(msg.sender == _owner, Errors.CALLER_IS_NOT_OWNER);
	}

	// Reverts if the "swap lock" is not engaged. Not made a modifier in order to work well with
	// the gas-saving [slot6].
	function onlyLocked(uint8 locked) internal pure {
		_require(locked == UINT8_MAX, Errors.NOT_PAUSED);
	}

	// Reverts if the "swap lock" is engaged. Not made a modifier in order to work well with the
	// gas-saving [slot6].
	function notLocked(uint8 locked) internal pure {
		if (locked == UINT8_MAX) _revert(Errors.PAUSED);
	}

	// Checks if a given address is a contract, but always returns true
	// if [contr] is [address(this)]
	function isContract(IERC20 contr) internal view returns (bool) {
		if (address(contr) == address(this)) return true;
		uint size;
		assembly {
			size := extcodesize(contr)
		}
		return (size > 0);
	}

	// Multiplication technique by Remco Bloemen - MIT license
	// https://medium.com/wicketh/mathemagic-full-multiply-27650fec525d
	function safeMul(uint256 x, uint256 y) internal pure returns (uint256 r0) {
		uint256 r1;
		assembly {
			let mm := mulmod(x, y, not(0))
			r0 := mul(x, y)
			r1 := sub(sub(mm, r0), lt(mm, r0))
		}
		_require(r1 == 0, Errors.MUL_OVERFLOW);
	}

	// Necessary for working with [slot6.inCategoryTotals]. See ICommonStructs.sol for details.
	function bytes6ToUint16Arr(bytes6 _bytes) internal pure returns (uint16[3] memory num) {
		num[0] = uint16(bytes2(_bytes[0]) | (bytes2(_bytes[1]) >> 8));
		num[1] = uint16(bytes2(_bytes[2]) | (bytes2(_bytes[3]) >> 8));
		num[2] = uint16(bytes2(_bytes[4]) | (bytes2(_bytes[5]) >> 8));
	}

	// Necessary for working with [slot6.inCategoryTotals]. See ICommonStructs.sol for details.
	function uint16ArrToBytes6(uint16[3] memory num) internal pure returns (bytes6 _bytes) {
		_bytes = 
			bytes6(bytes2(num[0])) |
			(bytes6(bytes2(num[1])) >> 16) |
			(bytes6(bytes2(num[2])) >> 32);
	}
}