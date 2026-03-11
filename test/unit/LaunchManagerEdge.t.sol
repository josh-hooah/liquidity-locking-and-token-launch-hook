// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {LaunchManager} from "../../src/LaunchManager.sol";
import {LiquidityLockVault} from "../../src/LiquidityLockVault.sol";
import {ReasonCodes} from "../../src/libraries/ReasonCodes.sol";
import {UnlockPolicyLibrary} from "../../src/libraries/UnlockPolicyLibrary.sol";

import {LaunchManagerTestBase} from "../shared/LaunchManagerTestBase.sol";

contract LaunchManagerEdgeTest is LaunchManagerTestBase {
    function testBoundaryMaxTxExactAmountAllowed() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.maxTxAmountInLaunchWindow = 100;
        _createLaunch(p);

        launchManager.onBeforeSwap(key, address(0xBEEF), -100);

        vm.expectRevert(
            abi.encodeWithSelector(LaunchManager.LaunchConstraint.selector, poolId, ReasonCodes.LAUNCH_WINDOW_MAX_TX)
        );
        launchManager.onBeforeSwap(key, address(0xBEEF), -101);
    }

    function testCooldownBoundaryExactTimestamp() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.cooldownSecondsPerAddress = 60;
        _createLaunch(p);

        launchManager.onAfterSwap(key, address(0xCAFE), toBalanceDelta(-1_000, 1_000));

        vm.expectRevert(abi.encodeWithSelector(LaunchManager.LaunchConstraint.selector, poolId, ReasonCodes.COOLDOWN));
        launchManager.onBeforeSwap(key, address(0xCAFE), -100);

        vm.warp(block.timestamp + 60);
        launchManager.onBeforeSwap(key, address(0xCAFE), -100);
    }

    function testVolumeMilestoneExactHitOffByOne() external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        _createLaunch(p);

        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(-499, 500));
        assertEq(launchManager.advance(poolId), 0);

        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(-1, 0));
        assertEq(launchManager.advance(poolId), 2_000);
    }

    function testMilestonesOutOfOrderReverts() external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        p.volumeMilestones = new uint256[](2);
        p.unlockBpsAtMilestone = new uint16[](2);

        p.volumeMilestones[0] = 2_000;
        p.volumeMilestones[1] = 1_000;

        p.unlockBpsAtMilestone[0] = 1_000;
        p.unlockBpsAtMilestone[1] = 2_000;

        vm.expectRevert(UnlockPolicyLibrary.InvalidPolicy.selector);
        _createLaunch(p);
    }

    function testUnlockBpsOverflowReverts() external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        p.unlockBpsAtMilestone[0] = 10_001;

        vm.expectRevert(UnlockPolicyLibrary.InvalidPolicy.selector);
        _createLaunch(p);
    }

    function testAdvanceIdempotent() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeEpochSeconds = 10;
        p.timeUnlockBpsPerEpoch = 2_500;
        _createLaunch(p);

        vm.warp(block.timestamp + 10);
        uint16 first = launchManager.advance(poolId);
        uint16 second = launchManager.advance(poolId);

        assertEq(first, 5_000);
        assertEq(second, 5_000);

        vm.warp(block.timestamp + 10);
        uint16 third = launchManager.advance(poolId);
        assertEq(third, 7_500);
    }

    function testWithdrawBeforeUnlockReverts() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeCliffSeconds = 1 days;
        _createLaunch(p);

        tokenA.approve(address(vault), type(uint256).max);
        tokenB.approve(address(vault), type(uint256).max);

        launchManager.depositLockedLiquidity(poolId, 1_000 ether, 1_000 ether);

        vm.expectRevert(LiquidityLockVault.WithdrawExceedsUnlocked.selector);
        launchManager.withdrawUnlockedLiquidity(poolId, address(this), 1 ether, 0);
    }

    function testPauseUnpauseBehavior() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        _createLaunch(p);

        launchManager.setEmergencyPause(poolId, true);

        vm.expectRevert(abi.encodeWithSelector(LaunchManager.LaunchConstraint.selector, poolId, ReasonCodes.PAUSED));
        launchManager.onBeforeSwap(key, address(0xAAA), -1);

        launchManager.setEmergencyPause(poolId, false);
        launchManager.onBeforeSwap(key, address(0xAAA), -1);
    }

    function testPermissionBitMismatchExpectations() external {
        launchManager.setHook(address(0x1111));

        vm.expectRevert(
            abi.encodeWithSelector(LaunchManager.LaunchConstraint.selector, bytes32(0), ReasonCodes.INVALID_POLICY)
        );
        launchManager.createLaunch(key, _defaultConfig(), _timePolicy());
    }

    function testOnlyHookEnforced() external {
        _createLaunch(_timePolicy());
        launchManager.setHook(address(0xFEED));

        vm.expectRevert(LaunchManager.NotHook.selector);
        launchManager.onBeforeSwap(key, address(1), -1);
    }
}
