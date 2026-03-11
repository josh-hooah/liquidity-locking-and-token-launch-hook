// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";

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

import {LaunchManager} from "../src/LaunchManager.sol";
import {LaunchLockHook} from "../src/LaunchLockHook.sol";
import {LiquidityLockVault} from "../src/LiquidityLockVault.sol";
import {HookDeployer} from "../src/HookDeployer.sol";
import {MockLaunchERC20} from "../src/mocks/MockLaunchERC20.sol";
import {ILiquidityLockVault} from "../src/interfaces/ILiquidityLockVault.sol";
import {ILaunchManager} from "../src/interfaces/ILaunchManager.sol";

contract DemoLaunchLifecycle is Script {
    using PoolIdLibrary for PoolKey;

    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    struct DemoEnv {
        PoolManager poolManager;
        LiquidityLockVault vault;
        LaunchManager launchManager;
        HookDeployer hookDeployer;
        LaunchLockHook hook;
        PoolModifyLiquidityTest modifyLiquidityRouter;
        PoolSwapTest swapRouter;
        MockLaunchERC20 token0;
        MockLaunchERC20 token1;
        PoolKey key;
        bytes32 poolId;
    }

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);

        vm.startBroadcast(deployerPk);

        DemoEnv memory env = _deployEnv(deployer);
        _createLaunch(env);
        _initializePoolAndSeed(env);

        uint256 blockedSwaps = 0;
        uint256 allowedSwaps = 0;

        // Execute one allowed swap on-chain.
        env.swapRouter.swap(
            env.key,
            SwapParams({zeroForOne: true, amountSpecified: -int256(5e14), sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1}),
            PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}),
            ""
        );
        allowedSwaps++;

        // Stop broadcasting and simulate blocked attempts without failing script execution.
        vm.stopBroadcast();

        if (!_doSwap(env, -int256(2e15))) blockedSwaps++; // blocked by launch-window max-tx
        if (!_doSwap(env, -int256(1e14))) blockedSwaps++; // blocked by cooldown

        vm.startBroadcast(deployerPk);
        uint16 unlockedBps = env.launchManager.advance(env.poolId);

        (uint256 withdrawable0, uint256 withdrawable1) = env.vault.withdrawableAmounts(env.poolId);
        uint256 withdraw0 = withdrawable0 / 2;
        uint256 withdraw1 = withdrawable1 / 2;

        env.launchManager.withdrawUnlockedLiquidity(env.poolId, deployer, withdraw0, withdraw1);

        (uint256 remaining0, uint256 remaining1) = env.vault.withdrawableAmounts(env.poolId);

        vm.stopBroadcast();

        _printSummary(env, deployer, blockedSwaps, allowedSwaps, unlockedBps, withdraw0, withdraw1, remaining0, remaining1);
    }

    function _deployEnv(address deployer) internal returns (DemoEnv memory env) {
        env.poolManager = new PoolManager(deployer);
        env.vault = new LiquidityLockVault(deployer);
        env.launchManager = new LaunchManager(env.poolManager, ILiquidityLockVault(address(env.vault)), deployer);
        env.hookDeployer = new HookDeployer();

        env.vault.setManager(address(env.launchManager));

        uint160 flags = uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG);
        (address expectedHookAddress, bytes32 salt) = HookMiner.find(
            address(env.hookDeployer),
            flags,
            type(LaunchLockHook).creationCode,
            abi.encode(IPoolManager(address(env.poolManager)), ILaunchManager(address(env.launchManager)))
        );

        env.hook = LaunchLockHook(
            env.hookDeployer.deploy(salt, env.poolManager, ILaunchManager(address(env.launchManager)))
        );
        require(address(env.hook) == expectedHookAddress, "HOOK_MISMATCH");
        env.launchManager.setHook(address(env.hook));

        MockLaunchERC20 tokenA = new MockLaunchERC20("Launch Token", "LCH", 10_000_000 ether, deployer);
        MockLaunchERC20 tokenB = new MockLaunchERC20("Paired Token", "PAIR", 10_000_000 ether, deployer);

        (env.token0, env.token1) = address(tokenA) < address(tokenB) ? (tokenA, tokenB) : (tokenB, tokenA);

        env.modifyLiquidityRouter = new PoolModifyLiquidityTest(env.poolManager);
        env.swapRouter = new PoolSwapTest(env.poolManager);

        env.token0.approve(address(env.modifyLiquidityRouter), type(uint256).max);
        env.token1.approve(address(env.modifyLiquidityRouter), type(uint256).max);
        env.token0.approve(address(env.swapRouter), type(uint256).max);
        env.token1.approve(address(env.swapRouter), type(uint256).max);
        env.token0.approve(address(env.vault), type(uint256).max);
        env.token1.approve(address(env.vault), type(uint256).max);

        env.key = PoolKey({
            currency0: Currency.wrap(address(env.token0)),
            currency1: Currency.wrap(address(env.token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(env.hook))
        });

        env.poolId = PoolId.unwrap(env.key.toId());
    }

    function _createLaunch(DemoEnv memory env) internal {
        LaunchManager.LaunchConfigParams memory cfg = LaunchManager.LaunchConfigParams({
            launchStartTime: uint64(block.timestamp),
            launchEndTime: uint64(block.timestamp + 1 days),
            pairedAsset: address(env.token1),
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
        p.volumeMilestones = new uint256[](2);
        p.unlockBpsAtMilestone = new uint16[](2);
        p.volumeMilestones[0] = 2e12;
        p.unlockBpsAtMilestone[0] = 2_000;
        p.volumeMilestones[1] = 4e12;
        p.unlockBpsAtMilestone[1] = 4_000;

        env.launchManager.createLaunch(env.key, cfg, p);
    }

    function _initializePoolAndSeed(DemoEnv memory env) internal {
        env.poolManager.initialize(env.key, SQRT_PRICE_1_1);

        env.modifyLiquidityRouter.modifyLiquidity(
            env.key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)}),
            ""
        );

        env.launchManager.depositLockedLiquidity(env.poolId, 1_000 ether, 1_000 ether);
    }

    function _doSwap(DemoEnv memory env, int256 amountSpecified) internal returns (bool ok) {
        SwapParams memory params =
            SwapParams({zeroForOne: true, amountSpecified: amountSpecified, sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1});

        bytes memory callData = abi.encodeCall(
            PoolSwapTest.swap,
            (env.key, params, PoolSwapTest.TestSettings({takeClaims: false, settleUsingBurn: false}), bytes(""))
        );

        (ok,) = address(env.swapRouter).call(callData);
    }

    function _printSummary(
        DemoEnv memory env,
        address deployer,
        uint256 blockedSwaps,
        uint256 allowedSwaps,
        uint16 unlockedBps,
        uint256 withdraw0,
        uint256 withdraw1,
        uint256 remaining0,
        uint256 remaining1
    ) internal view {
        console2.log("DEMO_DEPLOYER", deployer);
        console2.log("DEMO_POOL_MANAGER", address(env.poolManager));
        console2.log("DEMO_VAULT", address(env.vault));
        console2.log("DEMO_LAUNCH_MANAGER", address(env.launchManager));
        console2.log("DEMO_HOOK", address(env.hook));
        console2.log("DEMO_POOL_ID", uint256(env.poolId));
        console2.log("DEMO_ALLOWED_SWAPS", allowedSwaps);
        console2.log("DEMO_BLOCKED_SWAPS", blockedSwaps);
        console2.log("DEMO_UNLOCKED_BPS", unlockedBps);
        console2.log("DEMO_WITHDRAWN_0", withdraw0);
        console2.log("DEMO_WITHDRAWN_1", withdraw1);
        console2.log("DEMO_REMAINING_UNLOCKABLE_0", remaining0);
        console2.log("DEMO_REMAINING_UNLOCKABLE_1", remaining1);
    }
}
