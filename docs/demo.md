# Demo Guide

## Local Full Demo
```bash
make demo-all
```

## Focused Demos
```bash
make demo-launch-window
make demo-unlock
```

## Testnet Demo
```bash
make demo-testnet
```

`demo-testnet` automatically:

- loads `.env`
- checks deployed system addresses
- deploys if missing via `deploy-testnet`
- runs demo using `USE_DEPLOYED_SYSTEM=true`

## End-to-End Lifecycle (What Judges Should See)

### Phase 1: Setup
- Script prints `PHASE_1_SETUP_COMPLETE`
- User perspective (creator): launch console ready, system connected

### Phase 2: Create Launch
- Script prints `PHASE_2_LAUNCH_CREATED`
- User perspective (creator): commits lock/unlock policy on-chain
- Logged policy params:
  - `POLICY_MAX_TX_LAUNCH_WINDOW`
  - `POLICY_COOLDOWN_SECONDS`
  - `POLICY_MILESTONE_*`

### Phase 3: Initialize + Lock Liquidity
- Script prints `PHASE_3_POOL_INITIALIZED_AND_LIQUIDITY_LOCKED`
- User perspective (creator): initial liquidity moved to vault custody

### Phase 4: Swap Window Behavior
- Script prints `PHASE_4_ALLOWED_SWAP_EXECUTED`
- Script logs blocked attempts:
  - `PHASE_4_BLOCKED_SWAP_MAX_TX`
  - `PHASE_4_BLOCKED_SWAP_COOLDOWN`
- User perspective (trader): compliant orders succeed, toxic attempts fail

### Phase 5: Permissionless Progression
- Script prints `PHASE_5_PERMISSIONLESS_ADVANCE_EXECUTED`
- User perspective (anyone): `advance()` updates deterministic unlock state

### Phase 6: Partial Withdrawal
- Script prints `PHASE_6_CREATOR_WITHDREW_UNLOCKED_PORTION`
- User perspective (creator): unlocked amount withdrawable, remainder still locked

## Output Contract
Demo output includes:

- deployed addresses
- blocked/allowed swap counts
- unlock progression bps
- withdrawn and remaining unlockable amounts
- tx hashes and explorer links
- per-transaction status/function/gas from broadcast metadata
