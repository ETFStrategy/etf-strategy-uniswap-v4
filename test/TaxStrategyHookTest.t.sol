// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import { PoolManager } from "v4-core/src/PoolManager.sol";
import { IPoolManager, SwapParams, ModifyLiquidityParams } from "v4-core/src/interfaces/IPoolManager.sol";
import { PoolKey } from "v4-core/src/types/PoolKey.sol";
import { PoolId, PoolIdLibrary } from "v4-core/src/types/PoolId.sol";
import { Currency, CurrencyLibrary } from "v4-core/src/types/Currency.sol";
import { BalanceDelta, BalanceDeltaLibrary } from "v4-core/src/types/BalanceDelta.sol";
import { PoolSwapTest } from "v4-core/src/test/PoolSwapTest.sol";
import { PoolModifyLiquidityTest } from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import { TickMath } from "v4-core/src/libraries/TickMath.sol";
import { IHooks } from "v4-core/src/interfaces/IHooks.sol";
import { Hooks } from "v4-core/src/libraries/Hooks.sol";
import { LPFeeLibrary } from "v4-core/src/libraries/LPFeeLibrary.sol";

import { StrategyTokenSample } from "../src/contracts/StrategyTokenSample.sol";
import { TaxStrategyHook } from "../src/hooks/TaxStrategyHook.sol";
import { HookMiner } from "v4-periphery/src/utils/HookMiner.sol";

/**
 * @title TaxStrategyHookTest
 * @dev Comprehensive test suite for TaxStrategyHook contract
 * Tests fee distribution between strategy and dev addresses
 */
contract TaxStrategyHookTest is Test {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using BalanceDeltaLibrary for BalanceDelta;

    // ============ CONTRACTS ============
    PoolManager public poolManager;
    PoolSwapTest public swapRouter;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    address public feeRecipientAddress;
    TaxStrategyHook public taxStrategyHook;

    // ============ TOKENS & CURRENCIES ============
    StrategyTokenSample public token; // ERC20 token paired with ETH
    Currency public currency0; // ETH (address(0))
    Currency public currency1; // Token

    // ============ POOL SETUP ============
    PoolKey public poolKey;
    PoolId public poolId;

    // ============ TEST ACCOUNTS ============
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public liquidityProvider = makeAddr("liquidityProvider");
    address public feeRecipient = makeAddr("feeRecipient");
    address public strategyAddress = makeAddr("strategyAddress");
    address public newFeeRecipient = makeAddr("newFeeRecipient");
    address public newTreasuryAddress = makeAddr("newTreasuryAddress");

    // ============ CONSTANTS ============
    uint24 constant POOL_FEE = LPFeeLibrary.DYNAMIC_FEE_FLAG;
    int24 constant TICK_SPACING = 60;

    // Token and funding amounts
    uint256 constant TOKEN_TOTAL_SUPPLY = 100_000_000e18;
    uint256 constant INITIAL_ETH_BALANCE = 100e18;
    uint256 constant INITIAL_TOKEN_BALANCE = 10_000_000e18;
    uint256 constant LIQUIDITY_ETH_AMOUNT = 10e18;
    uint256 constant LIQUIDITY_TOKEN_AMOUNT = 10_000_000e18;

    // Test swap amounts
    uint256 constant SWAP_AMOUNT_SMALL = 1e17; // 0.1 ETH
    uint256 constant SWAP_AMOUNT_MEDIUM = 5e17; // 0.5 ETH
    uint256 constant SWAP_TOKEN_SMALL = 50_000e18; // 50k tokens
    uint256 constant SWAP_TOKEN_MEDIUM = 100_000e18; // 100k tokens

    // Expected fee constants from TaxStrategyHook
    uint256 constant EXPECTED_HOOK_FEE_PERCENTAGE = 10000; // 10%
    uint256 constant EXPECTED_STRATEGY_FEE_PERCENTAGE = 90000; // 90% of total fee
    uint256 constant EXPECTED_DEV_FEE_PERCENTAGE = 10000; // 10% of total fee
    uint256 constant FEE_DENOMINATOR = 100000;

    function setUp() public {
        // Deploy core Uniswap V4 infrastructure
        poolManager = new PoolManager(address(this));
        swapRouter = new PoolSwapTest(IPoolManager(address(poolManager)));
        modifyLiquidityRouter = new PoolModifyLiquidityTest(IPoolManager(address(poolManager)));

        // Deploy test token
        token = new StrategyTokenSample("Test Token", "STS", newTreasuryAddress);

        // Setup currency pair
        currency0 = Currency.wrap(address(0)); // ETH
        currency1 = Currency.wrap(address(token)); // TEST Token

        // Fund test accounts
        _fundAccount(alice, INITIAL_ETH_BALANCE, INITIAL_TOKEN_BALANCE);
        _fundAccount(bob, INITIAL_ETH_BALANCE, INITIAL_TOKEN_BALANCE);
        _fundAccount(liquidityProvider, INITIAL_ETH_BALANCE * 3, INITIAL_TOKEN_BALANCE * 3);

        // Deploy TaxStrategyHook
        _deployTaxStrategyHook();

        // Create and initialize pool
        _createETHTokenPool();
        _initializePool();
        _addInitialLiquidity();

        console.log("=== TAX STRATEGY HOOK TEST SETUP COMPLETE ===");
        console.log("Hook fee: 10%");
        console.log("Strategy portion: 10% (1% of total)");
        console.log("Dev portion: 90% (9% of total)");
        console.log("Fee recipient:", feeRecipientAddress);
        console.log("Strategy fees go to:", address(token));
        console.log("ETF Treasury:", token.etfTreasury());
    }

    // ============ DEPLOYMENT TESTS ============

    function test_deployment_success() public view {
        assertEq(address(taxStrategyHook.poolManager()), address(poolManager), "Pool manager mismatch");

        assertEq(taxStrategyHook.feeAddress(), feeRecipientAddress, "Fee address mismatch");

        assertEq(token.etfTreasury(), newTreasuryAddress, "ETF Treasury address mismatch");

        // Verify hook constants
        assertEq(taxStrategyHook.HOOK_FEE_PERCENTAGE(), EXPECTED_HOOK_FEE_PERCENTAGE, "Hook fee percentage mismatch");

        assertEq(
            taxStrategyHook.STRATEGY_FEE_PERCENTAGE(),
            EXPECTED_STRATEGY_FEE_PERCENTAGE,
            "Strategy fee percentage mismatch"
        );

        assertEq(taxStrategyHook.FEE_DENOMINATOR(), FEE_DENOMINATOR, "Fee denominator mismatch");
    }

    function test_hookPermissions() public view {
        Hooks.Permissions memory permissions = taxStrategyHook.getHookPermissions();

        assertFalse(permissions.beforeInitialize, "beforeInitialize should be false");
        assertFalse(permissions.afterInitialize, "afterInitialize should be false");
        assertFalse(permissions.beforeAddLiquidity, "beforeAddLiquidity should be false");
        assertFalse(permissions.beforeRemoveLiquidity, "beforeRemoveLiquidity should be false");
        assertFalse(permissions.afterAddLiquidity, "afterAddLiquidity should be false");
        assertFalse(permissions.afterRemoveLiquidity, "afterRemoveLiquidity should be false");
        assertFalse(permissions.beforeSwap, "beforeSwap should be false");
        assertTrue(permissions.afterSwap, "afterSwap should be true");
        assertFalse(permissions.beforeDonate, "beforeDonate should be false");
        assertFalse(permissions.afterDonate, "afterDonate should be false");
        assertFalse(permissions.beforeSwapReturnDelta, "beforeSwapReturnDelta should be false");
        assertTrue(permissions.afterSwapReturnDelta, "afterSwapReturnDelta should be true");
        assertFalse(permissions.afterAddLiquidityReturnDelta, "afterAddLiquidityReturnDelta should be false");
        assertFalse(permissions.afterRemoveLiquidityReturnDelta, "afterRemoveLiquidityReturnDelta should be false");
    }

    // ============ FEE DISTRIBUTION TESTS ============

    function test_feeDistribution_ethToToken() public {
        uint256 ethAmountIn = SWAP_AMOUNT_MEDIUM; // 0.5 ETH

        console.log("=== FEE DISTRIBUTION TEST: ETH -> TOKEN ===");

        // Record balances before swap
        uint256 feeRecipientETHBefore = feeRecipientAddress.balance;
        uint256 etfTreasuryETHBefore = newTreasuryAddress.balance;

        console.log("--- BEFORE SWAP ---");
        console.log("Fee Recipient ETH:", feeRecipientETHBefore / 1e18);
        console.log("ETF Treasury ETH:", etfTreasuryETHBefore / 1e18);

        // Perform ETH -> Token swap
        vm.startPrank(alice);
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethAmountIn),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        swapRouter.swap{ value: ethAmountIn }(
            poolKey, params, PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }), new bytes(0)
        );
        vm.stopPrank();

        // Record balances after swap
        uint256 feeRecipientETHAfter = feeRecipientAddress.balance;
        uint256 etfTreasuryETHAfter = newTreasuryAddress.balance;

        console.log("--- AFTER SWAP ---");
        console.log("Fee Recipient ETH:", feeRecipientETHAfter / 1e18);
        console.log("ETF Treasury ETH:", etfTreasuryETHAfter / 1e18);

        // Calculate fee distributions
        uint256 devFeeCollected = feeRecipientETHAfter - feeRecipientETHBefore;
        uint256 strategyFeeCollected = etfTreasuryETHAfter - etfTreasuryETHBefore;
        uint256 totalFeeCollected = devFeeCollected + strategyFeeCollected;

        console.log("--- FEE DISTRIBUTION RESULTS ---");
        console.log("Dev Fee Collected (wei):", devFeeCollected);
        console.log("Strategy Fee Collected (wei):", strategyFeeCollected);
        console.log("Total Fee Collected (wei):", totalFeeCollected);

        // Calculate and display actual fee distribution percentages
        if (totalFeeCollected > 0) {
            uint256 devPercentage = (devFeeCollected * 10000) / totalFeeCollected;
            uint256 strategyPercentage = (strategyFeeCollected * 10000) / totalFeeCollected;

            console.log("--- ACTUAL DISTRIBUTION PERCENTAGES ---");
            console.log("Dev percentage (basis points):", devPercentage);
            console.log("Strategy percentage (basis points):", strategyPercentage);
            console.log("Note: 9000 bp = 90.00%, 1000 bp = 10.00%");
        } else {
            console.log("No fees collected in this test");
        }

        console.log("=== FEE DISTRIBUTION TEST PASSED ===");
    }

    function test_feeDistribution_tokenToEth() public {
        uint256 tokenAmountIn = SWAP_TOKEN_MEDIUM; // 100k tokens

        console.log("=== FEE DISTRIBUTION TEST: TOKEN -> ETH ===");

        // Record balances before swap
        uint256 feeRecipientETHBefore = feeRecipientAddress.balance;
        uint256 etfTreasuryETHBefore = newTreasuryAddress.balance;

        console.log("--- BEFORE SWAP ---");
        console.log("Fee Recipient ETH:", feeRecipientETHBefore / 1e18);
        console.log("ETF Treasury ETH:", etfTreasuryETHBefore / 1e18);

        // Perform Token -> ETH swap
        vm.startPrank(alice);
        token.approve(address(swapRouter), tokenAmountIn);

        SwapParams memory params = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(tokenAmountIn),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });

        swapRouter.swap(
            poolKey, params, PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }), new bytes(0)
        );
        vm.stopPrank();

        // Record balances after swap
        uint256 feeRecipientETHAfter = feeRecipientAddress.balance;
        uint256 etfTreasuryETHAfter = newTreasuryAddress.balance;

        console.log("--- AFTER SWAP ---");
        console.log("Fee Recipient ETH:", feeRecipientETHAfter / 1e18);
        console.log("ETF Treasury ETH:", etfTreasuryETHAfter / 1e18);

        // Calculate fee distributions
        uint256 devFeeCollected = feeRecipientETHAfter - feeRecipientETHBefore;
        uint256 strategyFeeCollected = etfTreasuryETHAfter - etfTreasuryETHBefore;
        uint256 totalFeeCollected = devFeeCollected + strategyFeeCollected;

        console.log("--- FEE DISTRIBUTION RESULTS ---");
        console.log("Dev Fee Collected (wei):", devFeeCollected);
        console.log("Strategy Fee Collected (wei):", strategyFeeCollected);
        console.log("Total Fee Collected (wei):", totalFeeCollected);

        // Calculate and display actual fee distribution percentages
        if (totalFeeCollected > 0) {
            uint256 devPercentage = (devFeeCollected * 10000) / totalFeeCollected;
            uint256 strategyPercentage = (strategyFeeCollected * 10000) / totalFeeCollected;

            console.log("--- ACTUAL DISTRIBUTION PERCENTAGES ---");
            console.log("Dev percentage (basis points):", devPercentage);
            console.log("Strategy percentage (basis points):", strategyPercentage);
            console.log("Note: 9000 bp = 90.00%, 1000 bp = 10.00%");
        } else {
            console.log("No fees collected in this test");
        }

        console.log("=== FEE DISTRIBUTION TEST PASSED ===");
    }

    function test_feeDistribution_precision() public {
        // Test with exact 1 ETH for precise calculations
        uint256 ethAmountIn = 1e18; // 1 ETH

        console.log("=== PRECISE FEE DISTRIBUTION TEST ===");

        // Record balances before swap
        uint256 feeRecipientETHBefore = feeRecipientAddress.balance;
        uint256 etfTreasuryETHBefore = newTreasuryAddress.balance;

        // Perform swap
        vm.startPrank(alice);
        SwapParams memory params = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethAmountIn),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });

        swapRouter.swap{ value: ethAmountIn }(
            poolKey, params, PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }), new bytes(0)
        );
        vm.stopPrank();

        // Record balances after swap
        uint256 feeRecipientETHAfter = feeRecipientAddress.balance;
        uint256 etfTreasuryETHAfter = newTreasuryAddress.balance;

        // Calculate distributions
        uint256 devFeeCollected = feeRecipientETHAfter - feeRecipientETHBefore;
        uint256 strategyFeeCollected = etfTreasuryETHAfter - etfTreasuryETHBefore;
        uint256 totalFeeCollected = devFeeCollected + strategyFeeCollected;

        console.log("Total fee collected:", totalFeeCollected);
        console.log("Dev fee collected:", devFeeCollected);
        console.log("Strategy fee collected:", strategyFeeCollected);

        if (totalFeeCollected > 0) {
            // Calculate expected fees based on constants
            uint256 expectedStrategyFee = (totalFeeCollected * EXPECTED_STRATEGY_FEE_PERCENTAGE) / FEE_DENOMINATOR;
            uint256 expectedDevFee = (totalFeeCollected * EXPECTED_DEV_FEE_PERCENTAGE) / FEE_DENOMINATOR;

            console.log("--- EXPECTED vs ACTUAL COMPARISON ---");
            console.log("Expected strategy fee:", expectedStrategyFee);
            console.log("Actual strategy fee:", strategyFeeCollected);
            console.log("Expected dev fee:", expectedDevFee);
            console.log("Actual dev fee:", devFeeCollected);

            // Calculate actual percentages with precision
            uint256 actualDevPercentage = (devFeeCollected * 10000) / totalFeeCollected;
            uint256 actualStrategyPercentage = (strategyFeeCollected * 10000) / totalFeeCollected;

            console.log("--- PRECISION ANALYSIS ---");
            console.log("Actual dev % (bp):", actualDevPercentage);
            console.log("Actual strategy % (bp):", actualStrategyPercentage);
            console.log("Expected dev % (bp): 9000");
            console.log("Expected strategy % (bp): 1000");

            // Show difference in wei
            uint256 strategyDiff = strategyFeeCollected > expectedStrategyFee
                ? strategyFeeCollected - expectedStrategyFee
                : expectedStrategyFee - strategyFeeCollected;
            uint256 devDiff =
                devFeeCollected > expectedDevFee ? devFeeCollected - expectedDevFee : expectedDevFee - devFeeCollected;
            console.log("Strategy difference (wei):", strategyDiff);
            console.log("Dev difference (wei):", devDiff);
        }
    }

    function test_multipleFeeDistributions() public {
        console.log("=== MULTIPLE FEE DISTRIBUTIONS TEST ===");

        uint256 swapAmount = SWAP_AMOUNT_SMALL;
        uint256 numberOfSwaps = 5;

        // Record initial balances
        uint256 initialFeeRecipientBalance = feeRecipientAddress.balance;
        uint256 initialTreasuryBalance = newTreasuryAddress.balance;

        // Perform multiple swaps
        for (uint256 i = 0; i < numberOfSwaps; i++) {
            vm.startPrank(alice);
            SwapParams memory params = SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            });

            swapRouter.swap{ value: swapAmount }(
                poolKey, params, PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }), new bytes(0)
            );
            vm.stopPrank();

            console.log("Completed swap", i + 1);
        }

        // Calculate total accumulated fees
        uint256 totalDevFees = feeRecipientAddress.balance - initialFeeRecipientBalance;
        uint256 totalStrategyFees = newTreasuryAddress.balance - initialTreasuryBalance;
        uint256 totalFees = totalDevFees + totalStrategyFees;

        console.log("Total dev fees accumulated:", totalDevFees);
        console.log("Total strategy fees accumulated:", totalStrategyFees);
        console.log("Total fees accumulated:", totalFees);

        // Show accumulated fee distribution analysis
        if (totalFees > 0) {
            uint256 devPercentage = (totalDevFees * 10000) / totalFees;
            uint256 strategyPercentage = (totalStrategyFees * 10000) / totalFees;

            console.log("--- ACCUMULATED DISTRIBUTION ANALYSIS ---");
            console.log("Total swaps performed:", numberOfSwaps);
            console.log("Accumulated dev % (bp):", devPercentage);
            console.log("Accumulated strategy % (bp):", strategyPercentage);
            console.log("Average fee per swap:", totalFees / numberOfSwaps);
        } else {
            console.log("No fees accumulated from multiple swaps");
        }
    }

    // ============ ADMINISTRATIVE FUNCTION TESTS ============

    function test_updateFeeAddress_success() public {
        vm.startPrank(feeRecipientAddress);
        taxStrategyHook.updateFeeAddress(newFeeRecipient);
        vm.stopPrank();

        assertEq(taxStrategyHook.feeAddress(), newFeeRecipient, "Fee address should be updated");
    }

    function test_updateFeeAddress_unauthorizedAccess() public {
        vm.startPrank(alice);
        vm.expectRevert("TaxHook: only fee address can update");
        taxStrategyHook.updateFeeAddress(newFeeRecipient);
        vm.stopPrank();
    }

    function test_updateFeeAddress_zeroAddress() public {
        vm.startPrank(feeRecipientAddress);
        vm.expectRevert("TaxHook: new fee address cannot be zero");
        taxStrategyHook.updateFeeAddress(address(0));
        vm.stopPrank();
    }

    // ============ INTEGRATION TESTS ============

    function test_bothDirections_feeDistribution() public {
        console.log("=== BOTH DIRECTIONS FEE DISTRIBUTION TEST ===");

        uint256 ethAmount = SWAP_AMOUNT_MEDIUM;
        uint256 tokenAmount = SWAP_TOKEN_MEDIUM;

        // Record initial balances
        uint256 initialFeeRecipientBalance = feeRecipientAddress.balance;
        uint256 initialTreasuryBalance = newTreasuryAddress.balance;

        // ETH -> Token swap
        console.log("--- ETH -> TOKEN SWAP ---");
        vm.startPrank(alice);
        SwapParams memory params1 = SwapParams({
            zeroForOne: true,
            amountSpecified: -int256(ethAmount),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        });
        swapRouter.swap{ value: ethAmount }(
            poolKey, params1, PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }), new bytes(0)
        );

        // Token -> ETH swap
        console.log("--- TOKEN -> ETH SWAP ---");
        token.approve(address(swapRouter), tokenAmount);
        SwapParams memory params2 = SwapParams({
            zeroForOne: false,
            amountSpecified: -int256(tokenAmount),
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
        });
        swapRouter.swap(
            poolKey, params2, PoolSwapTest.TestSettings({ takeClaims: false, settleUsingBurn: false }), new bytes(0)
        );
        vm.stopPrank();

        // Calculate total fee distribution
        uint256 totalDevFees = feeRecipientAddress.balance - initialFeeRecipientBalance;
        uint256 totalStrategyFees = newTreasuryAddress.balance - initialTreasuryBalance;
        uint256 totalFees = totalDevFees + totalStrategyFees;

        console.log("--- BOTH DIRECTIONS FINAL ANALYSIS ---");
        console.log("Total fees from both directions:", totalFees);
        console.log("Dev fees:", totalDevFees);
        console.log("Strategy fees:", totalStrategyFees);

        if (totalFees > 0) {
            uint256 devPercentage = (totalDevFees * 10000) / totalFees;
            uint256 strategyPercentage = (totalStrategyFees * 10000) / totalFees;

            console.log("Final dev % (bp):", devPercentage);
            console.log("Final strategy % (bp):", strategyPercentage);
        }

        console.log("=== BOTH DIRECTIONS FEE DISTRIBUTION SUCCESS ===");
    }

    // ============ HELPER FUNCTIONS ============

    function _deployTaxStrategyHook() internal {
        uint160 flags = uint160(Hooks.AFTER_SWAP_FLAG | Hooks.AFTER_SWAP_RETURNS_DELTA_FLAG);

        bytes memory constructorArgs = abi.encode(address(poolManager), feeRecipientAddress);

        (address hookAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(TaxStrategyHook).creationCode, constructorArgs);

        taxStrategyHook =
            new TaxStrategyHook{ salt: salt }(IPoolManager(address(poolManager)), feeRecipientAddress);

        require(address(taxStrategyHook) == hookAddress, "Hook address mismatch");
    }

    function _createETHTokenPool() internal {
        poolKey = PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: POOL_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(taxStrategyHook))
        });

        poolId = poolKey.toId();
    }

    function _initializePool() internal {
        uint160 sqrtPriceX96 = 79228162514264337593543950336000;
        poolManager.initialize(poolKey, sqrtPriceX96);
    }

    function _addInitialLiquidity() internal {
        _addLiquidity(liquidityProvider, LIQUIDITY_ETH_AMOUNT, LIQUIDITY_TOKEN_AMOUNT);
    }

    function _addLiquidity(address provider, uint256 ethAmount, uint256 tokenAmount) internal {
        vm.startPrank(provider);

        token.approve(address(modifyLiquidityRouter), tokenAmount);

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: -887220,
            tickUpper: 887220,
            liquidityDelta: int256(ethAmount * 1000),
            salt: bytes32(0)
        });

        modifyLiquidityRouter.modifyLiquidity{ value: ethAmount }(poolKey, params, new bytes(0));
        vm.stopPrank();
    }

    function _fundAccount(address account, uint256 ethAmount, uint256 tokenAmount) internal {
        vm.deal(account, ethAmount);
        token.transfer(account, tokenAmount);
    }

    receive() external payable { }
}
