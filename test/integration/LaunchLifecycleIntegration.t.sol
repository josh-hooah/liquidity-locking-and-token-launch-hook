// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {ModifyLiquidityParams, SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "@uniswap/v4-core/src/test/PoolSwapTest.sol";

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";

import {LaunchManager} from "../../src/LaunchManager.sol";
import {LaunchLockHook} from "../../src/LaunchLockHook.sol";
import {LiquidityLockVault} from "../../src/LiquidityLockVault.sol";
import {HookDeployer} from "../../src/HookDeployer.sol";
import {MockLaunchERC20} from "../../src/mocks/MockLaunchERC20.sol";
import {ILiquidityLockVault} from "../../src/interfaces/ILiquidityLockVault.sol";
import {ILaunchManager} from "../../src/interfaces/ILaunchManager.sol";

contract LaunchLifecycleIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    PoolManager internal poolManager;
    LaunchManager internal launchManager;
    LiquidityLockVault internal vault;
    HookDeployer internal hookDeployer;
    LaunchLockHook internal hook;

    PoolModifyLiquidityTest internal modifyLiquidityRouter;
    PoolSwapTest internal swapRouter;

    MockLaunchERC20 internal token0;
    MockLaunchERC20 internal token1;

    PoolKey internal key;
    bytes32 internal poolId;

    address internal trader = address(0xB0B);

    function setUp() public {
        poolManager = new PoolManager(address(this));
        vault = new LiquidityLockVault(address(this));
        launchManager = new LaunchManager(poolManager, ILiquidityLockVault(address(vault)), address(this));
        vault.setManager(address(launchManager));

        hookDeployer = new HookDeployer();

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        (address expectedAddress, bytes32 salt) = HookMiner.find(
            address(hookDeployer),
            flags,
            type(LaunchLockHook).creationCode,
            abi.encode(IPoolManager(address(poolManager)), launchManager)
        );

        hook = LaunchLockHook(hookDeployer.deploy(salt, poolManager, ILaunchManager(address(launchManager))));
        assertEq(address(hook), expectedAddress);

        launchManager.setHook(address(hook));

        token0 = new MockLaunchERC20("Launch Token", "LCH", 1e30, address(this));
        token1 = new MockLaunchERC20("Paired Token", "PAIR", 1e30, address(this));

        (address low, address high) = address(token0) < address(token1)
            ? (address(token0), address(token1))
            : (address(token1), address(token0));

        token0 = MockLaunchERC20(low);
        token1 = MockLaunchERC20(high);

        modifyLiquidityRouter = new PoolModifyLiquidityTest(poolManager);
        swapRouter = new PoolSwapTest(poolManager);

        token0.approve(address(modifyLiquidityRouter), type(uint256).max);
        token1.approve(address(modifyLiquidityRouter), type(uint256).max);
        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);

        token0.mint(trader, 1e25);
        token1.mint(trader, 1e25);

        vm.startPrank(trader);
        token0.approve(address(swapRouter), type(uint256).max);
        token1.approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });

        poolId = PoolId.unwrap(key.toId());

        LaunchManager.LaunchConfigParams memory cfg = LaunchManager.LaunchConfigParams({
            launchStartTime: uint64(block.timestamp - 1),
            launchEndTime: uint64(block.timestamp + 1 days),
            pairedAsset: address(token1),
            referenceTick: 0
        });

        LaunchManager.UnlockPolicyParams memory p;
        p.mode = LaunchManager.UnlockMode.VOLUME;
        p.timeCliffSeconds = 0;
        p.timeEpochSeconds = 1;
        p.timeUnlockBpsPerEpoch = 1;
        p.minTradeSizeForVolume = 1;
        p.maxTxAmountInLaunchWindow = 1e15;
        p.cooldownSecondsPerAddress = 30;
        p.stabilityBandTicks = 0;
        p.stabilityMinDurationSeconds = 0;
        p.emergencyPause = false;
        p.volumeMilestones = new uint256[](1);
        p.unlockBpsAtMilestone = new uint16[](1);
        p.volumeMilestones[0] = 2e12;
        p.unlockBpsAtMilestone[0] = 2_000;

        launchManager.createLaunch(key, cfg, p);

        poolManager.initialize(key, SQRT_PRICE_1_1);

        modifyLiquidityRouter.modifyLiquidity(
            key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)}),
            ""
        );

        launchManager.depositLockedLiquidity(poolId, 1_000 ether, 1_000 ether);
    }

    function testAntiSnipeAndConditionalUnlockLifecycle() external {
        vm.startPrank(trader);

        vm.expectRevert();
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(2e15), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        swapRouter.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(5e14), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        vm.expectRevert();
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(1e14), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        vm.stopPrank();

        vm.warp(block.timestamp + 30);

        vm.prank(trader);
        swapRouter.swap(
            key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(2e14), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );

        uint16 unlocked = launchManager.advance(poolId);
        assertGe(unlocked, 2_000);

        (uint256 withdrawable0, uint256 withdrawable1) = vault.withdrawableAmounts(poolId);
        assertGt(withdrawable0 + withdrawable1, 0);

        launchManager.withdrawUnlockedLiquidity(poolId, address(this), withdrawable0 / 2, withdrawable1 / 2);

        (uint256 rem0, uint256 rem1) = vault.withdrawableAmounts(poolId);
        assertLe(rem0, withdrawable0);
        assertLe(rem1, withdrawable1);

        vm.expectRevert(LiquidityLockVault.WithdrawExceedsUnlocked.selector);
        launchManager.withdrawUnlockedLiquidity(poolId, address(this), rem0 + 1, 0);
    }
}
