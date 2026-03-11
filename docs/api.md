# API

## LaunchManager
- `createLaunch`
- `setPolicy`
- `setEmergencyPause`
- `depositLockedLiquidity`
- `advance`
- `withdrawUnlockedLiquidity`
- `onBeforeSwap` (hook-only)
- `onAfterSwap` (hook-only)

## LiquidityLockVault
- `deposit` (manager-only)
- `syncUnlockedBps` (manager-only)
- `withdrawTo` (manager-only)
- `withdrawableAmounts`

## LaunchLockHook
- `beforeSwap`
- `afterSwap`
