# Architecture

## Components
- `LaunchLockHook`: swap hook entrypoint for enforcement and accounting callbacks
- `LaunchManager`: launch registry, policy engine, unlock progression
- `LiquidityLockVault`: custody and bounded withdrawals

## Call Flow
1. `PoolManager -> LaunchLockHook.beforeSwap`
2. `LaunchLockHook -> LaunchManager.onBeforeSwap`
3. Swap executes in pool manager
4. `PoolManager -> LaunchLockHook.afterSwap`
5. `LaunchLockHook -> LaunchManager.onAfterSwap`
6. Any actor may call `LaunchManager.advance`
7. Vault unlock state syncs via `syncUnlockedBps`
