// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;

import {IERC20} from "@balancer-labs/v2-solidity-utils/contracts/openzeppelin/IERC20.sol";

/// @title Common data structures for the SW DAO Balancer pool
/// @author Peter T. Flynn
/// @notice Maintains a common interface between [CustomBalancerPool], and [ExtraStorage]
interface ICommonStructs {
	// Enumerates the different categories which pool-managed tokens can be assigned to:
	// NULL) Reserved as the default state, which indicates that the token is un-managed.
	// PRODUCT) Indicates that the token is an SW DAO product.
	// COMMON) Indicates that the token is "common", such as WETH, WMATIC, LINK, etc., but that it
	//		   is not USD-related like USDC, USDT, etc.
	// USD) Indicates that the token is related national currencies, such as USDC, USDT, etc.
	// BASE) Indicates that the token is either the BPT, or SWD. Other tokens are not assignable to
	//		 this category, and the tokens of this category cannot be re-weighted, or removed.
	// These categories are more useful as "guidelines" than hard-and-fast separations, and they
	// exist for the benefit of the pool's manager.
	// Since the three, primary categories appear in binary as 0001, 0010, and 0011, we can use a
	// binary trick to detect valid categories. [TokenCategory & 0x3 == 0] only returns true
	// for [NULL], and [BASE], as [NULL] is 0000, [BASE] is 0100, and [0x3] is 0011.
	enum TokenCategory{ NULL, PRODUCT, COMMON, USD, BASE }

	// Saves gas by packing small, often-used variables into a single 32-byte slot
	struct Slot6 {
		// The contract's owner
		address owner;
		// The number of tokens managed by the pool, including the BPT, and SWD
		uint8 tokensLength;
		// The current, flat fee used to maintain the token balances according to the configured
		// weights, expressed in tenths of a percent (ex. 10 = 1%). Can also be set to
		// 255 (type(uint8).max) to indicate that the "swap lock" is engaged, in which case the
		// balance fee can be found in [balanceFeeCache].
		uint8 balanceFee;
		// The weights of the three, primary categories
		// (DAO Products, Common Tokens, and USD-related tokens) relative to one another
		// (ex. [1, 1, 1] would grant 1/3 of the pool to each category).
		// See [enum TokenCategory] above for details on categories.
		// Stored as bytes3, but utilized as if it were uint8[3], in order to pack tightly.
		bytes3 categoryWeights;
		// The sum of all [categoryWeights]
		uint8 categoryWeightsTotal;
		// The sum of all individual, token wights within a given category.
		// Stored as bytes6, but utilized as if it were uint16[3], in order to pack tightly.
		// Helper functions bytes6ToUint16Arr(), and uint16ArrToBytes6() exist within
		// [ExtraStorage] to help with conversion.
		bytes6 inCategoryTotals;
	}

	// Used by various functions to store information about token pricing
	struct TokenValuation {
		// The price of the token in USD, with 18-decimals of precision
		uint price;
		// The total USD value of all such tokens managed by the pool
		uint total;
	}

	// Useful only for avoiding "stack too deep" errors
	struct GetValue {
		uint totalMinusSWD;
		uint bpt;
		TokenValuation indexIn;
		TokenValuation indexOut;
	}

	// Contains data about a "tier" of pricing, usually contained in a fixed-size array of length 3.
	// Each tier represents a balance state, as described in ExtraStorage.onSwapGetComplexPricing().
	// A [price] of 0, combined with an [amount] of 0 indicates that no such tier is reachable;
	// as, depending on the type of trade, the trade may only reach one, or two tiers.
	struct ComplexPricing {
		// The price per token, offered within this tier
		uint price;
		// The amount of tokens available within this tier, where 0 represents infinity
		uint amount;
	}

	// Utilized in an [IERC20 => TokenInfo] mapping for quickly retrieving category, and weight
	// information about a given token
	struct TokenInfo {
		TokenCategory category;
		uint8 inCategoryWeight;
	}

	// Useful only for avoiding "stack too deep" errors
	struct TokenData {
		uint indexIn;
		uint indexOut;
		TokenInfo inInfo;
		TokenInfo outInfo;
	}

	// Useful for passing pricing data between the various onSwap() child functions
	struct IndexPricing {
		ComplexPricing[3] indexIn;
		ComplexPricing[3] indexOut;
	}
}