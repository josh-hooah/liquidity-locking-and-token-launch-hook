# Liquidity Locking & Token Launch Hook - Specification

## 1. Scope
This system implements deterministic liquidity locking for launch pools with swap-time anti-snipe enforcement and permissionless unlock progression.

Components:

- `LaunchLockHook`: minimal swap hook
- `LaunchManager`: policy engine and launch state machine
- `LiquidityLockVault`: locked asset custody and withdrawal bounds
- `UnlockPolicyLibrary`: deterministic policy validation and unlock math

## 2. Design Principles
- Hook remains minimal and stateless-heavy logic is pushed to manager/vault.
- No offchain automation required for correctness.
- Progression is permissionless (`advance()`).
- Unlock state is monotonic and capped at `10000 bps`.

## 3. Core Data Model

### LaunchConfig
- `poolId`
- `launchStartTime`
- `launchEndTime`
- `pairedAsset`
- `creator`
- `policyNonce`
- `enabled`

### UnlockPolicy
- `mode` (`TIME`, `VOLUME`, `HYBRID`)
- `timeCliffSeconds`
- `timeEpochSeconds`
- `timeUnlockBpsPerEpoch`
- `minTradeSizeForVolume`
- `maxTxAmountInLaunchWindow`
- `cooldownSecondsPerAddress`
- `stabilityBandTicks`
- `stabilityMinDurationSeconds`
- `emergencyPause`
- `volumeMilestones[]`
- `unlockBpsAtMilestone[]`

### LaunchState
- `totalLiquidityLocked`
- `unlockedBps`
- `cumulativeVolumeToken0`
- `cumulativeVolumeToken1`
- `lastUnlockTimestamp`
- `lastProgressBlock`
- `referenceTick`
- `stableSinceTimestamp`
- `status`

## 4. Unlock Logic

### Time mode
Unlocks in epoch steps after cliff:

`timeBps = min(10000, ((elapsedAfterCliff/epoch)+1) * timeUnlockBpsPerEpoch)`

### Volume mode
Unlocks against sorted milestone arrays.

### Hybrid mode
Uses conservative composition:

`combinedBps = min(timeBps, volumeBps)`

### Stability gating
If configured, unlock progression is blocked unless:

- current tick is within `referenceTick ± stabilityBandTicks`
- in-band duration is at least `stabilityMinDurationSeconds`

## 5. Swap-Time Enforcement
During launch window:

- block swap when `abs(amountSpecified) > maxTxAmountInLaunchWindow`
- block swap when per-address cooldown is active

After swap:

- update per-address last swap time (for cooldown launches)
- update deterministic volume counters from absolute deltas
- update stability window tracking

## 6. Vault Model
Vault holds underlying launch assets and enforces:

`withdrawn <= totalLocked * unlockedBps / 10000`

Properties:

- manager-only state mutation
- non-reentrant withdrawal path
- monotonic `unlockedBps`

## 7. Security Properties
- only hook can call swap accounting checks
- only manager can mutate vault lock/unlock state
- unlock progression idempotent and monotonic
- policy misconfig rejected on creation/update

## 8. Residual Risks
- wash trading can still influence VBU despite min-trade filters
- per-address cooldown can be bypassed through address-splitting
- admin can still exercise pause/policy powers

## 9. Dependency Reproducibility
Pinned commits are enforced by `scripts/bootstrap.sh` and CI.

## 10. Testing Requirements Mapping
Implemented test classes:

- unit edge cases for policy bounds and launch-window boundaries
- fuzz for monotonic unlock and volume counter growth
- integration lifecycle with real v4 pool + routers + hook callbacks
