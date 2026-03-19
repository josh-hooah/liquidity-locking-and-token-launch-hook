// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {toBalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {LaunchManager} from "../../src/LaunchManager.sol";
import {LiquidityLockVault} from "../../src/LiquidityLockVault.sol";
import {MockLaunchERC20} from "../../src/mocks/MockLaunchERC20.sol";
import {ILiquidityLockVault} from "../../src/interfaces/ILiquidityLockVault.sol";
import {UnlockPolicyLibrary} from "../../src/libraries/UnlockPolicyLibrary.sol";

import {LaunchManagerTestBase} from "../shared/LaunchManagerTestBase.sol";

contract UnlockPolicyLibraryHarness {
    function validate(
        uint8 mode,
        uint64 timeEpochSeconds,
        uint16 timeUnlockBpsPerEpoch,
        uint256[] calldata volumeMilestones,
        uint16[] calldata unlockBpsAtMilestone
    ) external pure {
        UnlockPolicyLibrary.validate(mode, timeEpochSeconds, timeUnlockBpsPerEpoch, volumeMilestones, unlockBpsAtMilestone);
    }
}

contract CoverageBranchTargetsTest is LaunchManagerTestBase {
    function testConstructorZeroPoolManagerReverts() external {
        vm.expectRevert(LaunchManager.ZeroAddress.selector);
        new LaunchManager(IPoolManager(address(0)), ILiquidityLockVault(address(vault)), address(this));
    }

    function testConstructorZeroVaultReverts() external {
        vm.expectRevert(LaunchManager.ZeroAddress.selector);
        new LaunchManager(poolManager, ILiquidityLockVault(address(0)), address(this));
    }

    function testCreateLaunchWithoutHookConfiguredReverts() external {
        LaunchManager managerWithoutHook = new LaunchManager(poolManager, ILiquidityLockVault(address(vault)), address(this));

        vm.expectRevert(LaunchManager.ZeroAddress.selector);
        managerWithoutHook.createLaunch(key, _defaultConfig(), _timePolicy());
    }

    function testAdvanceCoversBothProgressAndNoProgressBranches() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeEpochSeconds = 1;
        p.timeUnlockBpsPerEpoch = 500;
        _createLaunch(p);

        vm.warp(block.timestamp + 1);
        uint16 progressed = launchManager.advance(poolId);
        uint16 unchanged = launchManager.advance(poolId);

        assertGt(progressed, 0);
        assertEq(unchanged, progressed);
    }

    function testOnlyHookModifierRevertPathOnAfterSwap() external {
        _createLaunch(_timePolicy());
        launchManager.setHook(address(0xCAFE));

        vm.expectRevert(LaunchManager.NotHook.selector);
        launchManager.onAfterSwap(key, address(0xBEEF), toBalanceDelta(-1, 1));
    }

    function testPolicyValidationInvalidModeReverts() external {
        UnlockPolicyLibraryHarness harness = new UnlockPolicyLibraryHarness();
        uint256[] memory milestones = new uint256[](0);
        uint16[] memory unlocks = new uint16[](0);

        vm.expectRevert(UnlockPolicyLibrary.InvalidPolicy.selector);
        harness.validate(3, 1, 1, milestones, unlocks);
    }

    function testPolicyValidationTimeWithZeroUnlockRateReverts() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeEpochSeconds = 1;
        p.timeUnlockBpsPerEpoch = 0;

        vm.expectRevert(UnlockPolicyLibrary.InvalidPolicy.selector);
        _createLaunch(p);
    }

    function testPolicyValidationTimeWithZeroEpochReverts() external {
        LaunchManager.UnlockPolicyParams memory p = _timePolicy();
        p.timeEpochSeconds = 0;
        p.timeUnlockBpsPerEpoch = 1;

        vm.expectRevert(UnlockPolicyLibrary.InvalidPolicy.selector);
        _createLaunch(p);
    }

    function testPolicyValidationVolumeLengthMismatchReverts() external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        p.volumeMilestones = new uint256[](1);
        p.unlockBpsAtMilestone = new uint16[](2);
        p.volumeMilestones[0] = 1_000;
        p.unlockBpsAtMilestone[0] = 1_000;
        p.unlockBpsAtMilestone[1] = 2_000;

        vm.expectRevert(UnlockPolicyLibrary.InvalidPolicy.selector);
        _createLaunch(p);
    }

    function testPolicyValidationVolumeDecreasingBpsReverts() external {
        LaunchManager.UnlockPolicyParams memory p = _volumePolicy();
        p.volumeMilestones = new uint256[](2);
        p.unlockBpsAtMilestone = new uint16[](2);
        p.volumeMilestones[0] = 1_000;
        p.volumeMilestones[1] = 2_000;
        p.unlockBpsAtMilestone[0] = 2_000;
        p.unlockBpsAtMilestone[1] = 1_000;

        vm.expectRevert(UnlockPolicyLibrary.InvalidPolicy.selector);
        _createLaunch(p);
    }

    function testVaultSyncUninitializedPoolRevertsForManager() external {
        vm.prank(address(launchManager));
        vm.expectRevert(LiquidityLockVault.InvalidPool.selector);
        vault.syncUnlockedBps(keccak256("uninitialized-pool"), 100);
    }

    function testVaultDepositToken1MismatchBranchReverts() external {
        bytes32 testPoolId = keccak256("token1-mismatch-branch");
        address orderedToken0 = Currency.unwrap(key.currency0);
        address orderedToken1 = Currency.unwrap(key.currency1);
        MockLaunchERC20(orderedToken0).approve(address(vault), type(uint256).max);
        MockLaunchERC20(orderedToken1).approve(address(vault), type(uint256).max);

        vm.prank(address(launchManager));
        vault.deposit(testPoolId, address(this), orderedToken0, orderedToken1, 1, 1);

        vm.prank(address(launchManager));
        vm.expectRevert(LiquidityLockVault.InvalidPool.selector);
        vault.deposit(testPoolId, address(this), orderedToken0, address(0xDEAD), 1, 0);
    }
}
