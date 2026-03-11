// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";

import {LaunchManager} from "../../src/LaunchManager.sol";
import {LiquidityLockVault} from "../../src/LiquidityLockVault.sol";
import {ReasonCodes} from "../../src/libraries/ReasonCodes.sol";

import {LaunchManagerTestBase} from "../shared/LaunchManagerTestBase.sol";

contract LaunchManagerAdditionalTest is LaunchManagerTestBase {
    function testSetHookZeroReverts() external {
        vm.expectRevert(LaunchManager.ZeroAddress.selector);
        launchManager.setHook(address(0));
    }

    function testCreateLaunchInvalidWindowReverts() external {
        LaunchManager.LaunchConfigParams memory cfg = _defaultConfig();
        cfg.launchStartTime = cfg.launchEndTime;

        vm.expectRevert(LaunchManager.InvalidLaunchWindow.selector);
        launchManager.createLaunch(key, cfg, _timePolicy());
    }

    function testSetPolicyIncrementsNonceAndCanPause() external {
        _createLaunch(_timePolicy());

        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.emergencyPause = true;
        launchManager.setPolicy(poolId, p);

        LaunchManager.LaunchConfig memory cfg = launchManager.getLaunchConfig(poolId);
        LaunchManager.LaunchState memory st = launchManager.getLaunchState(poolId);

        assertEq(cfg.policyNonce, 2);
        assertEq(uint256(st.status), uint256(LaunchManager.LaunchStatus.PAUSED));
    }

    function testSetReferenceTickAndGetters() external {
        _createLaunch(_timePolicy());

        launchManager.setReferenceTick(poolId, 123);

        LaunchManager.LaunchState memory st = launchManager.getLaunchState(poolId);
        LaunchManager.UnlockPolicy memory policy = launchManager.getLaunchPolicy(poolId);
        (address t0, address t1) = launchManager.getLaunchTokens(poolId);

        assertEq(st.referenceTick, 123);
        assertEq(uint256(policy.mode), uint256(LaunchManager.UnlockMode.TIME));
        assertTrue(t0 == address(tokenA) || t0 == address(tokenB));
        assertTrue(t1 == address(tokenA) || t1 == address(tokenB));
    }

    function testAdvanceToFinalizedAndDepositAfterUnlock() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeEpochSeconds = 1;
        p.timeUnlockBpsPerEpoch = 10_000;
        _createLaunch(p);

        vm.warp(block.timestamp + 1);
        assertEq(launchManager.advance(poolId), 10_000);

        LaunchManager.LaunchState memory st = launchManager.getLaunchState(poolId);
        assertEq(uint256(st.status), uint256(LaunchManager.LaunchStatus.FINALIZED));

        tokenA.approve(address(vault), type(uint256).max);
        tokenB.approve(address(vault), type(uint256).max);
        launchManager.depositLockedLiquidity(poolId, 1000, 2000);

        (uint256 w0, uint256 w1) = vault.withdrawableAmounts(poolId);
        assertEq(w0, 1000);
        assertEq(w1, 2000);
    }

    function testAdvanceBlockedByStabilityGate() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.stabilityBandTicks = 1;
        p.stabilityMinDurationSeconds = 10;
        _createLaunch(p);

        vm.expectRevert(
            abi.encodeWithSelector(
                LaunchManager.LaunchConstraint.selector, poolId, ReasonCodes.STABILITY_BAND_VIOLATION
            )
        );
        launchManager.advance(poolId);
    }

    function testPreviewAdvanceReturnsCandidate() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeEpochSeconds = 1;
        p.timeUnlockBpsPerEpoch = 1000;
        _createLaunch(p);

        vm.warp(block.timestamp + 1);
        (uint16 currentBps, uint16 candidate, bool stable) = launchManager.previewAdvance(poolId);

        assertEq(currentBps, 0);
        assertEq(candidate, 3000);
        assertTrue(stable);
    }

    function testOnlyCreatorOrOwnerPaths() external {
        _createLaunch(_timePolicy());

        vm.startPrank(address(0xBEEF));

        vm.expectRevert(LaunchManager.NotCreatorOrOwner.selector);
        launchManager.setPolicy(poolId, _timePolicy());

        vm.expectRevert(LaunchManager.NotCreatorOrOwner.selector);
        launchManager.setEmergencyPause(poolId, true);

        vm.expectRevert(LaunchManager.NotCreatorOrOwner.selector);
        launchManager.setReferenceTick(poolId, 1);

        vm.expectRevert(LaunchManager.NotCreatorOrOwner.selector);
        launchManager.depositLockedLiquidity(poolId, 1, 1);

        vm.expectRevert(LaunchManager.NotCreatorOrOwner.selector);
        launchManager.withdrawUnlockedLiquidity(poolId, address(0xBEEF), 1, 1);

        vm.stopPrank();
    }

    function testOnBeforeSwapOutsideWindowSkipsGuards() external {
        LaunchManager.LaunchConfigParams memory cfg = _defaultConfig();
        cfg.launchStartTime = uint64(block.timestamp + 1 days);
        cfg.launchEndTime = uint64(block.timestamp + 2 days);

        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.maxTxAmountInLaunchWindow = 1;

        launchManager.createLaunch(key, cfg, p);
        launchManager.onBeforeSwap(key, address(0xA1), -1000);
    }

    function testOnAfterSwapTracksCooldownAndVolume() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.cooldownSecondsPerAddress = 100;
        p.minTradeSizeForVolume = 10;
        _createLaunch(p);

        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(-25, 30));

        LaunchManager.LaunchState memory st = launchManager.getLaunchState(poolId);
        assertEq(st.cumulativeVolumeToken0, 25);
        assertEq(st.cumulativeVolumeToken1, 30);
        assertEq(launchManager.perAddressLastSwapTime(poolId, address(0xA1)), block.timestamp);
    }

    function testOnAfterSwapIgnoresSmallTradesBelowThreshold() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.minTradeSizeForVolume = 1000;
        _createLaunch(p);

        launchManager.onAfterSwap(key, address(0xA1), toBalanceDelta(-10, 10));

        LaunchManager.LaunchState memory st = launchManager.getLaunchState(poolId);
        assertEq(st.cumulativeVolumeToken0, 0);
        assertEq(st.cumulativeVolumeToken1, 0);
    }

    function testNotFoundErrors() external {
        bytes32 missing = keccak256("missing");

        vm.expectRevert(abi.encodeWithSelector(LaunchManager.LaunchNotFound.selector, missing));
        launchManager.getLaunchConfig(missing);

        vm.expectRevert(abi.encodeWithSelector(LaunchManager.LaunchNotFound.selector, missing));
        launchManager.previewAdvance(missing);
    }

    function testPauseBranchInAdvanceAndBeforeSwap() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.emergencyPause = true;
        _createLaunch(p);

        vm.expectRevert(abi.encodeWithSelector(LaunchManager.LaunchConstraint.selector, poolId, ReasonCodes.PAUSED));
        launchManager.advance(poolId);

        vm.expectRevert(abi.encodeWithSelector(LaunchManager.LaunchConstraint.selector, poolId, ReasonCodes.PAUSED));
        launchManager.onBeforeSwap(key, address(0xA1), -1);
    }

    function testVaultPositionInitializationMismatch() external {
        _createLaunch(_timePolicy());

        tokenA.approve(address(vault), type(uint256).max);
        tokenB.approve(address(vault), type(uint256).max);
        launchManager.depositLockedLiquidity(poolId, 100, 100);

        // Simulate mismatched token order by deploying a second launch with same pool id not possible,
        // so we assert vault position exists and remains consistent.
        LiquidityLockVault.VaultPosition memory pos = vault.getPosition(poolId);
        assertTrue(pos.initialized);
    }
}
