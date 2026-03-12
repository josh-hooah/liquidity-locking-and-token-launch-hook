// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";

import {LaunchManager} from "../../src/LaunchManager.sol";

import {LaunchManagerTestBase} from "../shared/LaunchManagerTestBase.sol";

contract CoverageCompletionTest is LaunchManagerTestBase {
    bytes32 internal constant POOLS_SLOT = bytes32(uint256(6));
    uint160 internal constant SQRT_PRICE_1_1 = 79228162514264337593543950336;

    function testCreateLaunchTwiceRevertsLaunchExists() external {
        _createLaunch(_timePolicy());

        vm.expectRevert(abi.encodeWithSelector(LaunchManager.LaunchExists.selector, poolId));
        launchManager.createLaunch(key, _defaultConfig(), _timePolicy());
    }

    function testStabilityBandTracksOutOfBandThenInBandAndPreviewChecksWindow() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.stabilityBandTicks = 5;
        p.stabilityMinDurationSeconds = 30;
        _createLaunch(p);

        _mockPoolTick(100);
        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(-25, 30));
        assertEq(launchManager.getLaunchState(poolId).stableSinceTimestamp, 0);

        _mockPoolTick(-1);
        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(-10, 11));
        uint64 stableSince = launchManager.getLaunchState(poolId).stableSinceTimestamp;
        assertGt(stableSince, 0);

        _mockPoolTick(100);
        (, uint16 candidateBlocked, bool stableBlocked) = launchManager.previewAdvance(poolId);
        assertFalse(stableBlocked);
        assertEq(candidateBlocked, launchManager.getLaunchState(poolId).unlockedBps);

        _mockPoolTick(0);
        vm.warp(uint256(stableSince) + p.stabilityMinDurationSeconds - 1);
        (, uint16 candidateEarly, bool stableEarly) = launchManager.previewAdvance(poolId);
        assertFalse(stableEarly);
        assertEq(candidateEarly, launchManager.getLaunchState(poolId).unlockedBps);

        vm.warp(uint256(stableSince) + p.stabilityMinDurationSeconds);
        (, , bool stableSatisfied) = launchManager.previewAdvance(poolId);
        assertTrue(stableSatisfied);
    }

    function testPreviewAdvanceClampsCandidateToCurrentUnlockedWhenPolicyLowersOutput() external {
        _createLaunch(_volumePolicy());

        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(-1000, 0));
        uint16 firstUnlock = launchManager.advance(poolId);
        assertEq(firstUnlock, 2_000);

        LaunchManager.UnlockPolicyParams memory lowered = _timePolicy();
        lowered.mode = LaunchManager.UnlockMode.TIME;
        lowered.timeEpochSeconds = 1 hours;
        lowered.timeUnlockBpsPerEpoch = 1_000;
        lowered.volumeMilestones = new uint256[](0);
        lowered.unlockBpsAtMilestone = new uint16[](0);

        launchManager.setPolicy(poolId, lowered);

        (uint16 current, uint16 candidate, bool stable) = launchManager.previewAdvance(poolId);
        assertTrue(stable);
        assertEq(current, 2_000);
        assertEq(candidate, 2_000);
    }

    function testPreviewAdvanceBeforeTimeCliffReturnsZero() external {
        LaunchManager.LaunchConfigParams memory cfg = _defaultConfig();
        cfg.launchStartTime = uint64(block.timestamp + 1 days);
        cfg.launchEndTime = uint64(block.timestamp + 2 days);

        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeCliffSeconds = 1 days;

        launchManager.createLaunch(key, cfg, p);

        (, uint16 candidate, bool stable) = launchManager.previewAdvance(poolId);
        assertTrue(stable);
        assertEq(candidate, 0);
    }

    function testVolumeModeAllowsZeroTimeParamsAndStillComputes() external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        p.timeEpochSeconds = 0;
        p.timeUnlockBpsPerEpoch = 0;
        _createLaunch(p);

        (, uint16 candidate, bool stable) = launchManager.previewAdvance(poolId);
        assertTrue(stable);
        assertEq(candidate, 0);
    }

    function _mockPoolTick(int24 tick) internal {
        bytes32 stateSlot = keccak256(abi.encodePacked(poolId, POOLS_SLOT));
        bytes32 slot0Word = _slot0Word(tick);

        vm.mockCall(
            address(poolManager), abi.encodeWithSignature("extsload(bytes32)", stateSlot), abi.encode(slot0Word)
        );
    }

    function _slot0Word(int24 tick) internal pure returns (bytes32) {
        uint256 tickBits = uint256(uint24(uint256(int256(tick))));
        uint256 word = uint256(SQRT_PRICE_1_1);
        word |= tickBits << 160;
        word |= uint256(3000) << 208;
        return bytes32(word);
    }
}
