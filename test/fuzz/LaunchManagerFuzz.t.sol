// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {LaunchManager} from "../../src/LaunchManager.sol";
import {LiquidityLockVault} from "../../src/LiquidityLockVault.sol";
import {LaunchManagerTestBase} from "../shared/LaunchManagerTestBase.sol";

contract LaunchManagerFuzzTest is LaunchManagerTestBase {
    function testFuzz_unlockedBpsMonotonicAndCapped(uint64 warpA, uint64 warpB, int128 d0, int128 d1) external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        p.mode = LaunchManager.UnlockMode.HYBRID;
        p.timeEpochSeconds = 120;
        p.timeUnlockBpsPerEpoch = 500;
        p.volumeMilestones = new uint256[](2);
        p.unlockBpsAtMilestone = new uint16[](2);
        p.volumeMilestones[0] = 1_000;
        p.volumeMilestones[1] = 10_000;
        p.unlockBpsAtMilestone[0] = 2_000;
        p.unlockBpsAtMilestone[1] = 6_000;

        _createLaunch(p);

        d0 = int128(bound(d0, -100_000, 100_000));
        d1 = int128(bound(d1, -100_000, 100_000));

        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(d0, d1));

        uint64 firstJump = uint64(bound(warpA, 0, 30 days));
        vm.warp(block.timestamp + firstJump);
        uint16 first = launchManager.advance(poolId);

        launchManager.onAfterSwap(key, address(0xA2), toBalanceDelta(d1, d0));

        uint64 secondJump = uint64(bound(warpB, firstJump, 60 days));
        vm.warp(block.timestamp + (secondJump - firstJump));
        uint16 second = launchManager.advance(poolId);

        assertLe(first, second);
        assertLe(second, 10_000);
    }

    function testFuzz_volumeCountersMonotonic(int128 a0, int128 a1, int128 b0, int128 b1) external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        p.minTradeSizeForVolume = 0;
        _createLaunch(p);

        a0 = int128(bound(a0, -1_000_000, 1_000_000));
        a1 = int128(bound(a1, -1_000_000, 1_000_000));
        b0 = int128(bound(b0, -1_000_000, 1_000_000));
        b1 = int128(bound(b1, -1_000_000, 1_000_000));

        LaunchManager.LaunchState memory s0 = launchManager.getLaunchState(poolId);
        launchManager.onAfterSwap(key, address(0x1), toBalanceDelta(a0, a1));
        LaunchManager.LaunchState memory s1 = launchManager.getLaunchState(poolId);

        launchManager.onAfterSwap(key, address(0x2), toBalanceDelta(b0, b1));
        LaunchManager.LaunchState memory s2 = launchManager.getLaunchState(poolId);

        assertGe(s1.cumulativeVolumeToken0, s0.cumulativeVolumeToken0);
        assertGe(s1.cumulativeVolumeToken1, s0.cumulativeVolumeToken1);
        assertGe(s2.cumulativeVolumeToken0, s1.cumulativeVolumeToken0);
        assertGe(s2.cumulativeVolumeToken1, s1.cumulativeVolumeToken1);
    }

    function testFuzz_withdrawNeverExceedsUnlocked(uint96 deposit0, uint96 deposit1, uint96 req0, uint96 req1) external {
        deposit0 = uint96(bound(deposit0, 1, 1_000_000e18));
        deposit1 = uint96(bound(deposit1, 1, 1_000_000e18));

        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeEpochSeconds = 1;
        p.timeUnlockBpsPerEpoch = 10_000;
        _createLaunch(p);

        tokenA.approve(address(vault), type(uint256).max);
        tokenB.approve(address(vault), type(uint256).max);

        launchManager.depositLockedLiquidity(poolId, deposit0, deposit1);
        vm.warp(block.timestamp + 1);
        launchManager.advance(poolId);

        (uint256 avail0, uint256 avail1) = vault.withdrawableAmounts(poolId);

        req0 = uint96(bound(req0, 0, uint96(type(uint96).max)));
        req1 = uint96(bound(req1, 0, uint96(type(uint96).max)));

        if (req0 <= avail0 && req1 <= avail1) {
            launchManager.withdrawUnlockedLiquidity(poolId, address(this), req0, req1);
            (uint256 rem0, uint256 rem1) = vault.withdrawableAmounts(poolId);
            assertEq(rem0, avail0 - req0);
            assertEq(rem1, avail1 - req1);
        } else {
            vm.expectRevert(LiquidityLockVault.WithdrawExceedsUnlocked.selector);
            launchManager.withdrawUnlockedLiquidity(poolId, address(this), req0, req1);
        }
    }
}
