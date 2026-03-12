// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {LiquidityLockVault} from "../../src/LiquidityLockVault.sol";
import {MockLaunchERC20} from "../../src/mocks/MockLaunchERC20.sol";

contract LiquidityLockVaultTest is Test {
    LiquidityLockVault internal vault;
    MockLaunchERC20 internal token0;
    MockLaunchERC20 internal token1;

    bytes32 internal poolId = keccak256("pool");
    address internal manager = address(0xABCD);

    function setUp() external {
        vault = new LiquidityLockVault(address(this));
        token0 = new MockLaunchERC20("T0", "T0", 1e30, address(this));
        token1 = new MockLaunchERC20("T1", "T1", 1e30, address(this));
        vault.setManager(manager);

        token0.approve(address(vault), type(uint256).max);
        token1.approve(address(vault), type(uint256).max);
    }

    function testSetManagerZeroReverts() external {
        vm.expectRevert(LiquidityLockVault.ZeroAddress.selector);
        vault.setManager(address(0));
    }

    function testOnlyManagerGuard() external {
        vm.expectRevert(LiquidityLockVault.NotManager.selector);
        vault.syncUnlockedBps(poolId, 1000);
    }

    function testDepositAndWithdrawFlow() external {
        vm.prank(manager);
        vault.deposit(poolId, address(this), address(token0), address(token1), 1000, 2000);

        vm.prank(manager);
        vault.syncUnlockedBps(poolId, 5000);

        (uint256 w0, uint256 w1) = vault.withdrawableAmounts(poolId);
        assertEq(w0, 500);
        assertEq(w1, 1000);

        vm.prank(manager);
        vault.withdrawTo(poolId, address(this), 300, 400);

        (uint256 rem0, uint256 rem1) = vault.withdrawableAmounts(poolId);
        assertEq(rem0, 200);
        assertEq(rem1, 600);
    }

    function testDepositInvalidPoolReverts() external {
        vm.prank(manager);
        vm.expectRevert(LiquidityLockVault.InvalidPool.selector);
        vault.deposit(bytes32(0), address(this), address(token0), address(token1), 1, 1);
    }

    function testNothingToDepositReverts() external {
        vm.prank(manager);
        vm.expectRevert(LiquidityLockVault.NothingToDeposit.selector);
        vault.deposit(poolId, address(this), address(token0), address(token1), 0, 0);
    }

    function testDepositTokenMismatchReverts() external {
        vm.prank(manager);
        vault.deposit(poolId, address(this), address(token0), address(token1), 1, 1);

        vm.prank(manager);
        vm.expectRevert(LiquidityLockVault.InvalidPool.selector);
        vault.deposit(poolId, address(this), address(token1), address(token0), 1, 1);
    }

    function testSyncInvalidBpsReverts() external {
        vm.prank(manager);
        vault.deposit(poolId, address(this), address(token0), address(token1), 1, 1);

        vm.prank(manager);
        vm.expectRevert(LiquidityLockVault.InvalidUnlockBps.selector);
        vault.syncUnlockedBps(poolId, 10_001);
    }

    function testSyncNotMonotonicReverts() external {
        vm.prank(manager);
        vault.deposit(poolId, address(this), address(token0), address(token1), 1, 1);

        vm.prank(manager);
        vault.syncUnlockedBps(poolId, 5000);

        vm.prank(manager);
        vm.expectRevert(LiquidityLockVault.UnlockNotMonotonic.selector);
        vault.syncUnlockedBps(poolId, 4000);
    }

    function testWithdrawInvalidPoolReverts() external {
        vm.prank(manager);
        vm.expectRevert(LiquidityLockVault.InvalidPool.selector);
        vault.withdrawTo(poolId, address(this), 1, 1);
    }

    function testWithdrawExceedsUnlockedReverts() external {
        vm.prank(manager);
        vault.deposit(poolId, address(this), address(token0), address(token1), 100, 100);

        vm.prank(manager);
        vault.syncUnlockedBps(poolId, 1000);

        vm.prank(manager);
        vm.expectRevert(LiquidityLockVault.WithdrawExceedsUnlocked.selector);
        vault.withdrawTo(poolId, address(this), 20, 20);
    }

    function testWithdrawableAmountsUninitializedPoolReturnsZero() external view {
        (uint256 amount0, uint256 amount1) = vault.withdrawableAmounts(keccak256("unknown-pool"));
        assertEq(amount0, 0);
        assertEq(amount1, 0);
    }
}
