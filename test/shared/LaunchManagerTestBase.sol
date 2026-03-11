// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";

import {LaunchManager} from "../../src/LaunchManager.sol";
import {LiquidityLockVault} from "../../src/LiquidityLockVault.sol";
import {MockLaunchERC20} from "../../src/mocks/MockLaunchERC20.sol";
import {ILiquidityLockVault} from "../../src/interfaces/ILiquidityLockVault.sol";

abstract contract LaunchManagerTestBase is Test {
    using PoolIdLibrary for PoolKey;

    PoolManager internal poolManager;
    LiquidityLockVault internal vault;
    LaunchManager internal launchManager;

    MockLaunchERC20 internal tokenA;
    MockLaunchERC20 internal tokenB;

    PoolKey internal key;
    bytes32 internal poolId;

    function setUp() public virtual {
        poolManager = new PoolManager(address(this));
        vault = new LiquidityLockVault(address(this));
        launchManager = new LaunchManager(poolManager, ILiquidityLockVault(address(vault)), address(this));

        vault.setManager(address(launchManager));
        launchManager.setHook(address(this));

        tokenA = new MockLaunchERC20("Launch A", "LA", 1e30, address(this));
        tokenB = new MockLaunchERC20("Launch B", "LB", 1e30, address(this));

        (address low, address high) = address(tokenA) < address(tokenB)
            ? (address(tokenA), address(tokenB))
            : (address(tokenB), address(tokenA));

        key = PoolKey({
            currency0: Currency.wrap(low),
            currency1: Currency.wrap(high),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(this))
        });

        poolId = PoolId.unwrap(key.toId());
    }

    function _defaultConfig() internal view returns (LaunchManager.LaunchConfigParams memory cfg) {
        cfg = LaunchManager.LaunchConfigParams({
            launchStartTime: uint64(block.timestamp - 1),
            launchEndTime: uint64(block.timestamp + 1 days),
            pairedAsset: address(tokenB),
            referenceTick: 0
        });
    }

    function _timePolicy() internal pure returns (LaunchManager.UnlockPolicyParams memory p) {
        p.mode = LaunchManager.UnlockMode.TIME;
        p.timeCliffSeconds = 0;
        p.timeEpochSeconds = 1 hours;
        p.timeUnlockBpsPerEpoch = 1000;
        p.minTradeSizeForVolume = 1;
        p.maxTxAmountInLaunchWindow = 1_000 ether;
        p.cooldownSecondsPerAddress = 0;
        p.stabilityBandTicks = 0;
        p.stabilityMinDurationSeconds = 0;
        p.emergencyPause = false;
        p.volumeMilestones = new uint256[](0);
        p.unlockBpsAtMilestone = new uint16[](0);
    }

    function _volumePolicy() internal pure returns (LaunchManager.UnlockPolicyParams memory p) {
        p.mode = LaunchManager.UnlockMode.VOLUME;
        p.timeCliffSeconds = 0;
        p.timeEpochSeconds = 1;
        p.timeUnlockBpsPerEpoch = 1;
        p.minTradeSizeForVolume = 1;
        p.maxTxAmountInLaunchWindow = 1_000 ether;
        p.cooldownSecondsPerAddress = 0;
        p.stabilityBandTicks = 0;
        p.stabilityMinDurationSeconds = 0;
        p.emergencyPause = false;
        p.volumeMilestones = new uint256[](1);
        p.volumeMilestones[0] = 1_000;
        p.unlockBpsAtMilestone = new uint16[](1);
        p.unlockBpsAtMilestone[0] = 2_000;
    }

    function _createLaunch(LaunchManager.UnlockPolicyParams memory p) internal {
        launchManager.createLaunch(key, _defaultConfig(), p);
    }
}
