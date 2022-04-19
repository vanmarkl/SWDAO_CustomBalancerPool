// SPDX-License-Identifier: Apache License 2.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "ds-test/test.sol";
import "../CustomBalancerPool.sol";
import "@balancer-labs/v2-solidity-utils/contracts/helpers/BalancerErrors.sol";
import "@balancer-labs/v2-vault/contracts/interfaces/IAsset.sol";

interface Hevm {
    function warp(uint256) external;
    // Set block.timestamp

    function roll(uint256) external;
    // Set block.number

    function fee(uint256) external;
    // Set block.basefee

    function load(address account, bytes32 slot) external returns (bytes32);
    // Loads a storage slot from an address

    function store(address account, bytes32 slot, bytes32 value) external;
    // Stores a value to an address' storage slot

    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    // Signs data

    function addr(uint256 privateKey) external returns (address);
    // Computes address for a given private key

    function ffi(string[] calldata) external returns (bytes memory);
    // Performs a foreign function call via terminal

    function prank(address) external;
    // Sets the *next* call's msg.sender to be the input address

    function startPrank(address) external;
    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called

    function prank(address, address) external;
    // Sets the *next* call's msg.sender to be the input address, and the tx.origin to be the second input

    function startPrank(address, address) external;
    // Sets all subsequent calls' msg.sender to be the input address until `stopPrank` is called, and the tx.origin to be the second input

    function stopPrank() external;
    // Resets subsequent calls' msg.sender to be `address(this)`

    function deal(address who, uint256 newBalance) external;
    // Sets an address' balance

    function etch(address who, bytes calldata code) external;
    // Sets an address' code

    function expectRevert() external;
    function expectRevert(bytes calldata) external;
    function expectRevert(bytes4) external;
    // Expects an error on next call

    function record() external;
    // Record all storage reads and writes

    function accesses(address) external returns (bytes32[] memory reads, bytes32[] memory writes);
    // Gets all accessed reads and write slot from a recording session, for a given address

    function expectEmit(bool, bool, bool, bool) external;
    // Prepare an expected log with (bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData).
    // Call this function, then emit an event, then call a function. Internally after the call, we check if
    // logs were emitted in the expected order with the expected topics and data (as specified by the booleans)

    function mockCall(address, bytes calldata, bytes calldata) external;
    // Mocks a call to an address, returning specified data.
    // Calldata can either be strict or a partial match, e.g. if you only
    // pass a Solidity selector to the expected calldata, then the entire Solidity
    // function will be mocked.

    function clearMockedCalls() external;
    // Clears all mocked calls

    function expectCall(address, bytes calldata) external;
    // Expect a call to an address with the specified calldata.
    // Calldata can either be strict or a partial match

    function getCode(string calldata) external returns (bytes memory);
    // Gets the bytecode for a contract in the project given the path to the contract.

    function label(address _addr, string calldata _label) external;
    // Label an address in test traces

    function assume(bool) external;
    // When fuzzing, generate new inputs if conditional not met
}

contract ContractTest_Pool is DSTest {

	Hevm constant VM = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
	address constant THISADDR = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

    IVault constant VAULT = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
    ITokenPriceControllerDefault constant ORACLE =
		ITokenPriceControllerDefault(0x8A46Eb6d66100138A5111b803189B770F5E5dF9a);

    IERC20 constant SWAP = IERC20(0x25Ad32265c9354c29e145c902aE876f6B69806F2);
	IERC20 constant SWYF = IERC20(0xDC8d88d9E57CC7bE548F76E5e413C4838F953018);
	IERC20 constant USDC = IERC20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IERC20 constant WETH = IERC20(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619);
    IERC20 constant WMATIC = IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
    IERC20 constant am3CRV = IERC20(0xE7a24EF0C5e95Ffb0f6684b813A78F2a3AD7D171);
	IERC20 constant SWD = IERC20(0xaeE24d5296444c007a532696aaDa9dE5cE6caFD0);

	address constant TREASURY = 0x480554E3e14Dd6b9d8C29298a9C57BB5fA51F926;

	CustomBalancerPool pool;

	function setUp() public {
        // Set to 18 decimals as workaround for RPC-fork bug
        VM.store(
            address(SWD),
            0x0000000000000000000000000000000000000000000000000000000000000038,
            0x0000000000000000000000000000000000000000000000000000000000000012
        );
        VM.label(0xBA12222222228d8Ba445958a75a0704d566BF2C8, "VAULT");
        VM.label(0x8A46Eb6d66100138A5111b803189B770F5E5dF9a, "ORACLE");
        VM.label(address(SWAP), "SWAP");
        VM.label(address(SWYF), "SWYF");
        VM.label(address(USDC), "USDC");
        VM.label(address(WETH), "WETH");
        VM.label(address(WMATIC), "WMATIC");
        VM.label(address(am3CRV), "am3CRV");
        VM.label(address(SWD), "SWD");
		pool = new CustomBalancerPool();
        // Simulate delegateCall from proxy.
        VM.store(
            address(pool),
            keccak256(abi.encode(uint16(100), 13)),
            0
        );
		pool.initialize("SW DAO Index", "SWDI");
        IERC20[] memory tokensAdd_tokens = new IERC20[](6);
        tokensAdd_tokens[0] = SWAP;
        tokensAdd_tokens[1] = SWYF;
        tokensAdd_tokens[2] = USDC;
        tokensAdd_tokens[3] = am3CRV;
        tokensAdd_tokens[4] = WETH;
        tokensAdd_tokens[5] = WMATIC;
        ICommonStructs.TokenCategory[] memory tokensAdd_categories = 
            new ICommonStructs.TokenCategory[](6);
        tokensAdd_categories[0] = ICommonStructs.TokenCategory.PRODUCT;
        tokensAdd_categories[1] = ICommonStructs.TokenCategory.PRODUCT;
        tokensAdd_categories[2] = ICommonStructs.TokenCategory.USD;
        tokensAdd_categories[3] = ICommonStructs.TokenCategory.USD;
        tokensAdd_categories[4] = ICommonStructs.TokenCategory.COMMON;
        tokensAdd_categories[5] = ICommonStructs.TokenCategory.COMMON;
        uint8[] memory tokensAdd_weights = new uint8[](6);
        tokensAdd_weights[0] = 1;
        tokensAdd_weights[1] = 1;
        tokensAdd_weights[2] = 1;
        tokensAdd_weights[3] = 9;
        tokensAdd_weights[4] = 2;
        tokensAdd_weights[5] = 1;
		pool.tokensAdd(tokensAdd_tokens, tokensAdd_categories, tokensAdd_weights);
	}

	function testFail_reInitialize() public {
		pool.initialize("SW DAO Index", "SWDI");
	}

    function test_tokensAdd() public {
        IERC20[] memory tokensAdd_tokens = new IERC20[](1);
        IERC20[] memory tokensAdd_tokens_bad = new IERC20[](2);
        ICommonStructs.TokenCategory[] memory tokensAdd_categories = 
            new ICommonStructs.TokenCategory[](1);
        tokensAdd_categories[0] = ICommonStructs.TokenCategory.COMMON;
        uint8[] memory tokensAdd_weights = new uint8[](1);
        tokensAdd_weights[0] = 1;
        VM.expectRevert("BAL#309");
        pool.tokensAdd(tokensAdd_tokens, tokensAdd_categories, tokensAdd_weights);
        //tokensAdd_tokens[0] = crvUSDBTCETH;
        //pool.tokensAdd(tokensAdd_tokens, tokensAdd_categories, tokensAdd_weights);
        tokensAdd_tokens[0] = USDC;
        VM.expectRevert("BAL#522");
        pool.tokensAdd(tokensAdd_tokens, tokensAdd_categories, tokensAdd_weights);
        pool.tokensRemove(tokensAdd_tokens);
        tokensAdd_categories[0] = ICommonStructs.TokenCategory.BASE;
        VM.expectRevert("BAL#309");
        pool.tokensAdd(tokensAdd_tokens, tokensAdd_categories, tokensAdd_weights);
        tokensAdd_categories[0] = ICommonStructs.TokenCategory.NULL;
        VM.expectRevert("BAL#309");
        pool.tokensAdd(tokensAdd_tokens, tokensAdd_categories, tokensAdd_weights);
        tokensAdd_categories[0] = ICommonStructs.TokenCategory.USD;
        pool.tokensAdd(tokensAdd_tokens, tokensAdd_categories, tokensAdd_weights);
        VM.expectRevert("BAL#103");
        pool.tokensAdd(tokensAdd_tokens_bad, tokensAdd_categories, tokensAdd_weights);
    }

    function test_tokensRemove() public {
        IERC20[] memory tokensRemove_tokens01 = new IERC20[](1);
        tokensRemove_tokens01[0] = WMATIC;
        pool.tokensRemove(tokensRemove_tokens01);
        ICommonStructs.TokenCategory[] memory tokensAdd_categories = 
            new ICommonStructs.TokenCategory[](1);
        tokensAdd_categories[0] = ICommonStructs.TokenCategory.COMMON;
        uint8[] memory tokensAdd_weights = new uint8[](1);
        tokensAdd_weights[0] = 1;
        pool.tokensAdd(tokensRemove_tokens01, tokensAdd_categories, tokensAdd_weights);
        IERC20[] memory tokensRemove_tokens02 = new IERC20[](3);
        tokensRemove_tokens02[0] = SWAP;
        tokensRemove_tokens02[1] = SWYF;
        tokensRemove_tokens02[2] = USDC;
        pool.tokensRemove(tokensRemove_tokens02);
        tokensRemove_tokens01[0] = SWAP;
        tokensAdd_categories[0] = ICommonStructs.TokenCategory.PRODUCT;
        pool.tokensAdd(tokensRemove_tokens01, tokensAdd_categories, tokensAdd_weights);
        tokensRemove_tokens02[0] = am3CRV;
        tokensRemove_tokens02[1] = WETH;
        tokensRemove_tokens02[2] = USDC;
        VM.expectRevert("BAL#309");
        pool.tokensRemove(tokensRemove_tokens02);
        tokensRemove_tokens02[0] = am3CRV;
        tokensRemove_tokens02[1] = WETH;
        tokensRemove_tokens02[2] = WMATIC;
        pool.tokensRemove(tokensRemove_tokens02);
        VM.expectRevert("BAL#200");
        pool.tokensRemove(tokensRemove_tokens01);
        tokensRemove_tokens01[0] = SWYF;
        pool.tokensAdd(tokensRemove_tokens01, tokensAdd_categories, tokensAdd_weights);
        tokensRemove_tokens01[0] = SWD;
        VM.expectRevert("BAL#309");
        pool.tokensRemove(tokensRemove_tokens01);
    }

    function test_setBalanceFee(uint8 x) public {
        if (x == 255)
            VM.expectRevert("NoMax");
        pool.setBalanceFee(x);
    }

    function test_setCategoryWeights(uint8 x, uint8 y, uint8 z) public {
        if (uint16(x) + uint16(y) + uint16(z) > 255)
            VM.expectRevert("BAL#000");
        pool.setCategoryWeights([x, y, z]);
        (,,,uint8[3] memory categoryWeights, uint8 categoryWeightsTotal,) = pool.getSlot6();
        require(
            uint16(x) + uint16(y) + uint16(z) > 255 ||
            (
                categoryWeightsTotal == x + y + z &&
                uint8(categoryWeights[0]) == x &&
                uint8(categoryWeights[1]) == y &&
                uint8(categoryWeights[2]) == z
            )
        );
    }

    function test_setTokenWeights(uint8 a, uint8 b, uint8 c, uint8 d, uint8 e, uint8 f) public {
        IERC20[] memory tokens = new IERC20[](6);
        tokens[0] = SWAP;
        tokens[1] = SWYF;
        tokens[2] = USDC;
        tokens[3] = am3CRV;
        tokens[4] = WETH;
        tokens[5] = WMATIC;
        uint8[] memory weights = new uint8[](6);
        weights[0] = a;
        weights[1] = b;
        weights[2] = c;
        weights[3] = d;
        weights[4] = e;
        weights[5] = f;
        pool.setTokenWeights(tokens, weights);
        (,,,,,uint16[3] memory inCategoryTotals) = pool.getSlot6();
        require(
            uint16(weights[0]) + uint16(weights[1]) == inCategoryTotals[0] &&
            uint16(weights[2]) + uint16(weights[3]) == inCategoryTotals[2] &&
            uint16(weights[4]) + uint16(weights[5]) == inCategoryTotals[1]
        );
    }

    function test_toggleSwapLock() public {
        VM.expectRevert("BAL#206");
        pool.toggleSwapLock();
        test_setCategoryWeights(4, 2, 1);
        test_onJoinPool_INIT();
        pool.toggleSwapLock();
    }

    function test_onJoinPool(
        uint128 a, uint128 b, uint128 c, uint128 d, uint128 e, uint128 f, uint128 g
    ) public {
        VM.assume(
            a > 0 &&
            (
                b > 0 ||
                c > 0 ||
                d > 0 ||
                e > 0 ||
                f > 0 ||
                g > 0
            )
        );
        VM.startPrank(address(VAULT));
        (IERC20[] memory tokens, uint[] memory balances,) = VAULT.getPoolTokens(pool.getPoolId());
        uint totalPrice;
        uint[] memory request = new uint[](balances.length);
        {
            request[1] = a;
            request[2] = b;
            request[3] = c;
            request[4] = d;
            request[5] = e;
            request[6] = f;
            request[7] = g;
            uint[] memory prices = new uint[](balances.length);
            for (uint i = 2; i < balances.length; i++) {
                (prices[i],) = ORACLE
                    .getManager(ERC20(address(tokens[i])).symbol())
                    .getPrice(ITokenPriceManagerMinimal.PriceType.RAW);
            }
            for (uint i = 2; i < balances.length; i++) {
                totalPrice += (request[i] * prices[i]) / (10**ERC20(address(tokens[i])).decimals());
            }
        }
        CustomBalancerPool.JoinKindPhantom joinKind = CustomBalancerPool.JoinKindPhantom.INIT;
        bytes memory userData = abi.encode(joinKind, request);
        bytes32 poolId = pool.getPoolId();
        log_named_decimal_uint("totalPrice", totalPrice, 18);
        if (totalPrice < 10000 * (10**18)) 
            VM.expectRevert("Min$20K");
        (uint[] memory amounts, uint[] memory fees) = pool.onJoinPool(
            poolId, address(this), address(this),
            balances, 0, 0, userData
        );
        if (totalPrice >= 10000 * (10**18)) {
            for (uint i; i < balances.length; i++) {
                require(fees[i] == 0);
            }
            require(
                amounts[0] > 0 &&
                amounts[1] == a &&
                amounts[2] == b &&
                amounts[3] == c &&
                amounts[4] == d &&
                amounts[5] == e &&
                amounts[6] == f &&
                amounts[7] == g
            );
        }
        joinKind = CustomBalancerPool.JoinKindPhantom.TOP_UP_BPT;
        userData = abi.encode(joinKind, request);
        (amounts, fees) = pool.onJoinPool(
            pool.getPoolId(), address(this), address(this), 
            balances, 0, 0, userData
        );
        require(amounts[0] > 0 && fees[0] == 0);
        for (uint i = 1; i < balances.length; i++) {
            require(
                amounts[i] == 0 &&
                fees[i] == 0
            );
        }
        VM.stopPrank();
    }

    function test_onJoinPool_INIT() public {
        (IERC20[] memory assets,,) = VAULT.getPoolTokens(pool.getPoolId());
        IAsset[] memory assets_conv = new IAsset[](assets.length);
        for (uint i; i < assets.length; i++)
            assets_conv[i] = IAsset(address(assets[i]));
        uint[] memory amountsIn = new uint[](assets.length);
        amountsIn[0] = type(uint).max;
        for (uint i = 2; i < assets.length; i++)
            amountsIn[i] = 100 * (10 ** ERC20(address(assets[i])).decimals());
        // SWD handled in a special case due to RPC errors. Will work normally in production.
        amountsIn[1] = 100 * (10**18);
        CustomBalancerPool.JoinKindPhantom joinKind = CustomBalancerPool.JoinKindPhantom.INIT;
        bytes memory userData = abi.encode(joinKind, amountsIn);
        IVault.JoinPoolRequest memory request =
            IVault.JoinPoolRequest(assets_conv, amountsIn, userData, false);
        fillBalances(address(this));
        setAllowances(address(VAULT));
        VAULT.joinPool(pool.getPoolId(), address(this), address(this), request);
    }

    function test_onJoinPool_COLLECT_PROTOCOL_FEES() public {
        test_onSwapValue(0);
        (, uint[] memory balances,) = VAULT.getPoolTokens(pool.getPoolId());
        uint _fees = pool.dueProtocolFees();
        require(_fees > 0);
        uint[] memory request = new uint[](balances.length);
        CustomBalancerPool.JoinKindPhantom joinKind = 
            CustomBalancerPool.JoinKindPhantom.COLLECT_PROTOCOL_FEES;
        bytes memory userData = abi.encode(joinKind, request);
        VM.startPrank(address(VAULT));
        (uint[] memory amounts, uint[] memory fees) = pool.onJoinPool(
            pool.getPoolId(), address(this), address(this),
            balances, 0, 0, userData
        );
        VM.stopPrank();
        for (uint i; i < amounts.length; i++)
            require(amounts[i] == 0);
        for (uint i = 1; i < fees.length; i++)
            require(fees[i] == 0);
        require(fees[0] == _fees);
        require(pool.dueProtocolFees() == 0);
    }

    function test_onJoinPool_TOP_UP_BPT() public {
        test_onSwapValue(0);
        (IERC20[] memory assets, uint[] memory balances,) = VAULT.getPoolTokens(pool.getPoolId());
        require(balances[0] < 0xffffffffffffffffffffffff);
        IAsset[] memory assets_conv = new IAsset[](assets.length);
        for (uint i; i < assets.length; i++)
            assets_conv[i] = IAsset(address(assets[i]));
        uint[] memory request = new uint[](balances.length);
        request[0] = type(uint).max;
        CustomBalancerPool.JoinKindPhantom joinKind = 
            CustomBalancerPool.JoinKindPhantom.TOP_UP_BPT;
        bytes memory userData = abi.encode(joinKind, request);
        IVault.JoinPoolRequest memory _request =
            IVault.JoinPoolRequest(assets_conv, request, userData, false);
        VAULT.joinPool(pool.getPoolId(), address(this), address(this), _request);
        (, balances,) = VAULT.getPoolTokens(pool.getPoolId());
        require(balances[0] == 0xffffffffffffffffffffffff);
    }

    function testFail_onJoinPool_UNHANDLED(uint8 x) public {
        VM.assume(x > 2);
        (IERC20[] memory assets,,) = VAULT.getPoolTokens(pool.getPoolId());
        IAsset[] memory assets_conv = new IAsset[](assets.length);
        for (uint i; i < assets.length; i++)
            assets_conv[i] = IAsset(address(assets[i]));
        uint[] memory amountsIn = new uint[](assets.length);
        amountsIn[0] = type(uint).max;
        for (uint i = 1; i < assets.length; i++)
            amountsIn[i] = 100 * (10 ** ERC20(address(assets[i])).decimals());
        bytes memory userData = abi.encode(x, amountsIn);
        IVault.JoinPoolRequest memory request =
            IVault.JoinPoolRequest(assets_conv, amountsIn, userData, false);
        fillBalances(address(this));
        setAllowances(address(VAULT));
        VAULT.joinPool(pool.getPoolId(), address(this), address(this), request);
    }

    function test_onExitPool(uint72 x) public {
        test_onJoinPool_INIT();
        (IERC20[] memory assets,,) = VAULT.getPoolTokens(pool.getPoolId());
        IAsset[] memory assets_conv = new IAsset[](assets.length);
        for (uint i; i < assets.length; i++)
            assets_conv[i] = IAsset(address(assets[i]));
        bytes memory userData = abi.encode(0, x);
        IVault.ExitPoolRequest memory request =
            IVault.ExitPoolRequest(assets_conv, new uint[](assets.length), userData, false);
        test_setCategoryWeights(4, 2, 1);
        (uint bptValue01, uint swdValue01) = pool.getValue();
        VAULT.exitPool(pool.getPoolId(), address(this), payable(address(this)), request);
        (uint bptValue02, uint swdValue02) = pool.getValue();
        require(
            roughlyEqual(bptValue01, bptValue02) &&
            roughlyEqual(swdValue01, swdValue02)
        );
        uint balance = pool.balanceOf(address(this));
        userData = abi.encode(0, balance);
        request = IVault.ExitPoolRequest(assets_conv, new uint[](assets.length), userData, false);
        VAULT.exitPool(pool.getPoolId(), address(this), payable(address(this)), request);
        (uint bptValue03, uint swdValue03) = pool.getValue();
        require(
            roughlyEqual(bptValue01, bptValue03) &&
            roughlyEqual(swdValue01, swdValue03)
        );
    }

    function testFail_onExitPool_UNHANDLED(uint8 x) public {
        VM.assume(x > 0);
        (IERC20[] memory assets,,) = VAULT.getPoolTokens(pool.getPoolId());
        IAsset[] memory assets_conv = new IAsset[](assets.length);
        for (uint i; i < assets.length; i++)
            assets_conv[i] = IAsset(address(assets[i]));
        bytes memory userData = abi.encode(x, 10);
        IVault.ExitPoolRequest memory request =
            IVault.ExitPoolRequest(assets_conv, new uint[](assets.length), userData, false);
        test_onJoinPool_INIT();
        test_setCategoryWeights(4, 2, 1);
        VAULT.exitPool(pool.getPoolId(), address(this), payable(address(this)), request);
    }

    function test_onSwap(uint8 a, uint8 b, bool inOut) public {
        a %= 8;
        b %= 8;
        VM.assume(!(a == 1 && b == 0) && (a != b));
        {
            (IERC20[] memory assets,,) = VAULT.getPoolTokens(pool.getPoolId());
            uint[] memory prices = new uint[](assets.length);
            for (uint i = 2; i < assets.length; i++) {
                (prices[i],) = ORACLE
                    .getManager(ERC20(address(assets[i])).symbol())
                    .getPrice(ITokenPriceManagerMinimal.PriceType.RAW);
            }
            IAsset[] memory assets_conv = new IAsset[](assets.length);
            for (uint i; i < assets.length; i++)
                assets_conv[i] = IAsset(address(assets[i]));
            uint[] memory amountsIn = new uint[](assets.length);
            amountsIn[0] = type(uint).max;
            amountsIn[1] = 2000 * (10**18);
            amountsIn[2] =
                (571429 * (10**ERC20(address(SWAP)).decimals()) * (10**16)) / prices[2];
            amountsIn[3] =
                (571429 * (10**ERC20(address(SWYF)).decimals()) * (10**16)) / prices[3];
            amountsIn[4] =
                (28571 * (10**ERC20(address(USDC)).decimals()) * (10**16)) / prices[4];
            amountsIn[5] =
                (257143 * (10**ERC20(address(am3CRV)).decimals()) * (10**16)) / prices[5];
            amountsIn[6] =
                (380953 * (10**ERC20(address(WETH)).decimals()) * (10**16)) / prices[6];
            amountsIn[7] =
                (190476 * (10**ERC20(address(WMATIC)).decimals()) * (10**16)) / prices[7];
            CustomBalancerPool.JoinKindPhantom joinKind = CustomBalancerPool.JoinKindPhantom.INIT;
            bytes memory userData = abi.encode(joinKind, amountsIn);
            IVault.JoinPoolRequest memory request =
                IVault.JoinPoolRequest(assets_conv, amountsIn, userData, false);
            fillBalances(address(this));
            setAllowances(address(VAULT));
            VAULT.joinPool(pool.getPoolId(), address(this), address(this), request);
            require(roughlyEqual(20000*(10**18), pool.balanceOf(address(this)) + 10*(10**18)));
        }
        test_setCategoryWeights(4, 2, 1);
        (IERC20[] memory tokens, uint[] memory balances,) = VAULT.getPoolTokens(pool.getPoolId());
        uint rawPriceIn;
        uint rawPriceOut;
        if (a < 2) {
            (uint bptValue, uint swdValue) = pool.getValue();
            rawPriceIn = (a == 0) ? bptValue : swdValue;
        } else {
            (rawPriceIn,) = ORACLE
                .getManager(ERC20(address(tokens[a])).symbol())
                .getPrice(ITokenPriceManagerMinimal.PriceType.RAW);
        }
        if (b < 2) {
            (uint bptValue, uint swdValue) = pool.getValue();
            rawPriceOut = (b == 0) ? bptValue : swdValue;
        } else {
            (rawPriceOut,) = ORACLE
                .getManager(ERC20(address(tokens[b])).symbol())
                .getPrice(ITokenPriceManagerMinimal.PriceType.RAW);
        }
        uint requestAmount = inOut ? 
            285 * (10**(18 + ERC20(address(tokens[b])).decimals())) :
            285 * (10**(18 + ERC20(address(tokens[a])).decimals()));
        requestAmount /= inOut ? rawPriceOut : rawPriceIn;
        uint pureReturn = inOut ? 
            285 * (10**(18 + ERC20(address(tokens[a])).decimals())) :
            285 * (10**(18 + ERC20(address(tokens[b])).decimals()));
        pureReturn /= inOut ? rawPriceIn : rawPriceOut;
        IVault.SwapKind swapKind = inOut ?
            IVault.SwapKind.GIVEN_OUT :
            IVault.SwapKind.GIVEN_IN;
        IPoolSwapStructs.SwapRequest memory swapRequest =
            IPoolSwapStructs.SwapRequest(
                swapKind,
                tokens[a],
                tokens[b],
                requestAmount,
                pool.getPoolId(),
                100,
                address(0),
                address(0),
                new bytes(1)
            );
        VM.expectRevert("BAL#205");
        pool.onSwap(swapRequest, balances, a, b);
        VM.startPrank(address(VAULT));
        VM.expectRevert("BAL#402");
        pool.onSwap(swapRequest, balances, a, b);
        VM.stopPrank();
        pool.setBalanceFee(4);
        pool.toggleSwapLock();
        VM.startPrank(address(VAULT));
        uint amount = pool.onSwap(swapRequest, balances, a, b);
        VM.stopPrank();
        {
            bool amountTest = inOut ?
                amount >= pureReturn :
                amount <= pureReturn;
            bool equalityTest = (a == 1 || b == 1) ?
                roughlyEqual(amount, pureReturn, 2) :
                roughlyEqual(amount, pureReturn);
            require(amountTest && equalityTest);
        }
        if (amount != pureReturn && !(a == 0 || b == 0)) {
            require(pool.dueProtocolFees() > 0);
        }
    }

    function test_onSwapValue(bytes32 x) public {
        IAsset[] memory assets_conv;
        {
            (IERC20[] memory assets,,) = VAULT.getPoolTokens(pool.getPoolId());
            uint[] memory prices = new uint[](assets.length);
            for (uint i = 2; i < assets.length; i++) {
                (prices[i],) = ORACLE
                    .getManager(ERC20(address(assets[i])).symbol())
                    .getPrice(ITokenPriceManagerMinimal.PriceType.RAW);
            }
            assets_conv = new IAsset[](assets.length);
            for (uint i; i < assets.length; i++)
                assets_conv[i] = IAsset(address(assets[i]));
            uint[] memory amountsIn = new uint[](assets.length);
            amountsIn[0] = type(uint).max;
            amountsIn[1] = 2000 * (10**18);
            amountsIn[2] =
                (571429 * (10**ERC20(address(SWAP)).decimals()) * (10**16)) / prices[2];
            amountsIn[3] =
                (571429 * (10**ERC20(address(SWYF)).decimals()) * (10**16)) / prices[3];
            amountsIn[4] =
                (28571 * (10**ERC20(address(USDC)).decimals()) * (10**16)) / prices[4];
            amountsIn[5] =
                (257143 * (10**ERC20(address(am3CRV)).decimals()) * (10**16)) / prices[5];
            amountsIn[6] =
                (380953 * (10**ERC20(address(WETH)).decimals()) * (10**16)) / prices[6];
            amountsIn[7] =
                (190476 * (10**ERC20(address(WMATIC)).decimals()) * (10**16)) / prices[7];
            CustomBalancerPool.JoinKindPhantom joinKind = CustomBalancerPool.JoinKindPhantom.INIT;
            bytes memory userData = abi.encode(joinKind, amountsIn);
            IVault.JoinPoolRequest memory request =
                IVault.JoinPoolRequest(assets_conv, amountsIn, userData, false);
            fillBalances(address(this));
            setAllowances(address(VAULT));
            VAULT.joinPool(pool.getPoolId(), address(this), address(this), request);
            require(roughlyEqual(20000*(10**18), pool.balanceOf(address(this)) + 10*(10**18)));
        }
        test_setCategoryWeights(4, 2, 1);
        pool.toggleSwapLock();
        IVault.FundManagement memory funds = IVault.FundManagement(
            address(this),
            false,
            payable(address(this)),
            false
        );
        (uint bptValue01,) = pool.getValue();
        uint bptValue02;
        //uint feesCache;
        for (uint i; i < 20; i++) {
            (, uint[] memory balances,) = VAULT.getPoolTokens(pool.getPoolId());
            VM.roll(block.number + 1);
            x = keccak256(abi.encodePacked(x));
            uint y = uint8(bytes1(x)) % 8;
            if (y == 1) y++;
            uint z = y;
            while (z == y) {
                x = keccak256(abi.encodePacked(x));
                z = uint8(bytes1(x)) % 8;
            }
            uint amount;
            IVault.SwapKind inOut;
            uint limit;
            if (y == 0) {
                inOut = IVault.SwapKind.GIVEN_IN;
                amount = uint(x) % pool.balanceOf(address(this));
            } else {
                inOut = IVault.SwapKind.GIVEN_OUT;
                if (balances[z] == 0) {
                    amount = 1 * 1e18;
                } else {
                    amount = (z == 0) ? 
                        uint(x) % balances[z] % (100000 * (10**18)) :
                        uint(x) % balances[z];
                }
                limit = type(uint).max;
            }
            IVault.SingleSwap memory singleSwap = IVault.SingleSwap(
                pool.getPoolId(),
                inOut,
                assets_conv[y],
                assets_conv[z],
                amount,
                new bytes(0)
            );
            //log_named_string("Traded", ERC20(address(assets_conv[y])).symbol());
            if (balances[z] == 0)
                VM.expectRevert("BAL#406");
            VAULT.swap(singleSwap, funds, limit, type(uint).max);
            //uint amountOut = VAULT.swap(singleSwap, funds, limit, type(uint).max);
            /*
            if (inOut == IVault.SwapKind.GIVEN_OUT) {
                log_named_decimal_uint("\tIn", amountOut, ERC20(address(assets_conv[y])).decimals());
            } else {
                log_named_decimal_uint("\tIn", amount, ERC20(address(assets_conv[y])).decimals());
            }
            log_named_string("For", ERC20(address(assets_conv[z])).symbol());
            if (inOut == IVault.SwapKind.GIVEN_OUT) {
                log_named_decimal_uint("\tOut", amount, ERC20(address(assets_conv[z])).decimals());
            } else {
                log_named_decimal_uint("\tOut", amountOut, ERC20(address(assets_conv[z])).decimals());
            }
            */
            (bptValue02,) = pool.getValue();
            //log_named_decimal_uint("Fees", pool.dueProtocolFees() - feesCache, 18);
            //feesCache = pool.dueProtocolFees();
            //log_named_decimal_uint("Current BPT Value", bptValue02, 18);
            //log_string("\n");
        }
        //log_named_decimal_uint("Initial BPT Value", bptValue01, 18);
        //log_named_decimal_uint("Due Fees", pool.dueProtocolFees(), 18);
        require(bptValue02 > bptValue01 || roughlyEqual(bptValue01, bptValue02));
    }

    function test_ownerTransfer(address a, bool b) public {
		VM.assume(a != address(this));
		pool.ownerTransfer(a);
		VM.startPrank(a, a);
		if (b) {
			VM.warp(block.timestamp + 37 hours);
			VM.expectRevert("BAL#209");
			pool.ownerConfirm();
		} else {
			pool.ownerConfirm();
			pool.ownerTransfer(address(this));
			VM.stopPrank();
			VM.expectRevert("BAL#426");
			pool.toggleSwapLock();
			pool.ownerConfirm();
		}
	}

    function fillBalances(address a) private {
        bytes32 MAX = bytes32(type(uint).max);
        VM.startPrank(0x01c6DEA91745d8C7a0cd2b4FA9d65ce04c94a20F, 0x01c6DEA91745d8C7a0cd2b4FA9d65ce04c94a20F);
        // SWD handled in a special case due to RPC errors. Will work normally in production.
        SWD.transfer(a, 100000 * (10**18));
        VM.stopPrank();
        require(SWD.balanceOf(a) == 100000 * (10**18));
        VM.store(
            address(SWAP),
            keccak256(abi.encode(a, 0)),
            MAX
        );
        VM.store(
            address(SWYF),
            keccak256(abi.encode(a, 0)),
            MAX
        );
        VM.store(
            address(WETH),
            keccak256(abi.encode(a, 0)),
            MAX
        );
        VM.store(
            address(WMATIC),
            keccak256(abi.encode(a, 3)),
            MAX
        );
        VM.store(
            address(USDC),
            keccak256(abi.encode(a, 0)),
            MAX
        );
        VM.store(
            address(am3CRV),
            keccak256(abi.encode(2, a)),
            MAX
        );
    }

    function setAllowances(address b) private {
        uint MAX = type(uint).max;
        SWD.approve(b, MAX);
        SWAP.approve(b, MAX);
        SWYF.approve(b, MAX);
        WETH.approve(b, MAX);
        WMATIC.approve(b, MAX);
        USDC.approve(b, MAX);
        am3CRV.approve(b, MAX);
    }

    function roughlyEqual(uint a, uint b) private pure returns (bool) {
        return roughlyEqual(a, b, 1);
    }

    function roughlyEqual(uint a, uint b, uint p) private pure returns (bool) {
        return 
            a >= ExtraStorage.safeMul(b, (100 - p)) / 100 && 
            a <= ExtraStorage.safeMul(b, (100 + p)) / 100;
    }
}