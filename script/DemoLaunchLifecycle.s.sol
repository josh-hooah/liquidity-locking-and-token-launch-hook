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
    uint256 internal constant INITIAL_LOCK_AMOUNT_0 = 1_000 ether;
    uint256 internal constant INITIAL_LOCK_AMOUNT_1 = 1_000 ether;

    struct DemoEnv {
        IPoolManager poolManager;
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
        bool usingDeployedSystem;
    }

    function run() external {
        uint256 deployerPk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPk);
        bool useDeployedSystem = vm.envOr("USE_DEPLOYED_SYSTEM", false);

        vm.startBroadcast(deployerPk);

        DemoEnv memory env = _setupEnv(deployer, useDeployedSystem);

        console2.log("PHASE_1_SETUP_COMPLETE");
        console2.log("USER_VIEW_CREATOR: system ready, launch wizard can start");

        _createLaunch(env);
        console2.log("PHASE_2_LAUNCH_CREATED");
        console2.log("USER_VIEW_CREATOR: launch policy committed onchain");

        _initializePoolAndSeed(env);
        console2.log("PHASE_3_POOL_INITIALIZED_AND_LIQUIDITY_LOCKED");
        console2.log("USER_VIEW_CREATOR: liquidity custody moved into vault");

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
        console2.log("PHASE_4_ALLOWED_SWAP_EXECUTED");
        console2.log("USER_VIEW_TRADER: valid swap succeeded");

        // Stop broadcasting and simulate blocked attempts without failing script execution.
        vm.stopBroadcast();

        if (!_doSwap(env, -int256(2e15))) {
            blockedSwaps++; // blocked by launch-window max-tx
            console2.log("PHASE_4_BLOCKED_SWAP_MAX_TX");
        }
        if (!_doSwap(env, -int256(1e14))) {
            blockedSwaps++; // blocked by cooldown
            console2.log("PHASE_4_BLOCKED_SWAP_COOLDOWN");
        }
        console2.log("USER_VIEW_TRADER: oversized and cooldown-violating swaps blocked");

        vm.startBroadcast(deployerPk);
        uint16 unlockedBps = env.launchManager.advance(env.poolId);
        console2.log("PHASE_5_PERMISSIONLESS_ADVANCE_EXECUTED");

        (uint256 withdrawable0, uint256 withdrawable1) = env.vault.withdrawableAmounts(env.poolId);
        uint256 withdraw0 = withdrawable0 / 2;
        uint256 withdraw1 = withdrawable1 / 2;

        env.launchManager.withdrawUnlockedLiquidity(env.poolId, deployer, withdraw0, withdraw1);
        console2.log("PHASE_6_CREATOR_WITHDREW_UNLOCKED_PORTION");
        console2.log("USER_VIEW_CREATOR: partially unlocked liquidity withdrawn, remainder still protected");

        (uint256 remaining0, uint256 remaining1) = env.vault.withdrawableAmounts(env.poolId);

        vm.stopBroadcast();

        _printSummary(env, deployer, blockedSwaps, allowedSwaps, unlockedBps, withdraw0, withdraw1, remaining0, remaining1);
    }

    function _setupEnv(address deployer, bool useDeployedSystem) internal returns (DemoEnv memory env) {
        env.usingDeployedSystem = useDeployedSystem;

        if (useDeployedSystem) {
            env.poolManager = IPoolManager(vm.envAddress("POOL_MANAGER_ADDRESS"));
            env.vault = LiquidityLockVault(vm.envAddress("LIQUIDITY_LOCK_VAULT_ADDRESS"));
            env.launchManager = LaunchManager(vm.envAddress("LAUNCH_MANAGER_ADDRESS"));
            env.hook = LaunchLockHook(vm.envAddress("LAUNCH_LOCK_HOOK_ADDRESS"));

            require(address(env.launchManager.poolManager()) == address(env.poolManager), "POOL_MANAGER_MISMATCH");
            require(address(env.launchManager.vault()) == address(env.vault), "VAULT_MISMATCH");
            require(env.launchManager.launchHook() == address(env.hook), "HOOK_MISMATCH");
        } else {
            env.poolManager = IPoolManager(address(new PoolManager(deployer)));
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
        }

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

        console2.log("DEMO_MODE", useDeployedSystem ? "USE_DEPLOYED_SYSTEM" : "DEPLOY_FRESH_SYSTEM");
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

        console2.log("POLICY_MODE=VOLUME");
        console2.log("POLICY_MAX_TX_LAUNCH_WINDOW", p.maxTxAmountInLaunchWindow);
        console2.log("POLICY_COOLDOWN_SECONDS", p.cooldownSecondsPerAddress);
        console2.log("POLICY_MILESTONE_0_VOLUME", p.volumeMilestones[0]);
        console2.log("POLICY_MILESTONE_0_BPS", p.unlockBpsAtMilestone[0]);
        console2.log("POLICY_MILESTONE_1_VOLUME", p.volumeMilestones[1]);
        console2.log("POLICY_MILESTONE_1_BPS", p.unlockBpsAtMilestone[1]);

        env.launchManager.createLaunch(env.key, cfg, p);
    }

    function _initializePoolAndSeed(DemoEnv memory env) internal {
        env.poolManager.initialize(env.key, SQRT_PRICE_1_1);

        env.modifyLiquidityRouter.modifyLiquidity(
            env.key,
            ModifyLiquidityParams({tickLower: -120, tickUpper: 120, liquidityDelta: 1e18, salt: bytes32(0)}),
            ""
        );

        env.launchManager.depositLockedLiquidity(env.poolId, INITIAL_LOCK_AMOUNT_0, INITIAL_LOCK_AMOUNT_1);
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
        console2.log("DEMO_MODE_USE_DEPLOYED_SYSTEM", env.usingDeployedSystem);
        console2.log("DEMO_POOL_MANAGER", address(env.poolManager));
        console2.log("DEMO_VAULT", address(env.vault));
        console2.log("DEMO_LAUNCH_MANAGER", address(env.launchManager));
        console2.log("DEMO_HOOK_DEPLOYER", address(env.hookDeployer));
        console2.log("DEMO_HOOK", address(env.hook));
        console2.log("DEMO_POOL_ID", uint256(env.poolId));
        console2.log("DEMO_LOCKED_AMOUNT_0", INITIAL_LOCK_AMOUNT_0);
        console2.log("DEMO_LOCKED_AMOUNT_1", INITIAL_LOCK_AMOUNT_1);
        console2.log("DEMO_ALLOWED_SWAPS", allowedSwaps);
        console2.log("DEMO_BLOCKED_SWAPS", blockedSwaps);
        console2.log("DEMO_UNLOCKED_BPS", unlockedBps);
        console2.log("DEMO_WITHDRAWN_0", withdraw0);
        console2.log("DEMO_WITHDRAWN_1", withdraw1);
        console2.log("DEMO_REMAINING_UNLOCKABLE_0", remaining0);
        console2.log("DEMO_REMAINING_UNLOCKABLE_1", remaining1);
    }
}
