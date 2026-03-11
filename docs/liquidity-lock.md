# Liquidity Lock

Vault locks underlying launch assets and permits withdrawals only within unlocked bounds.

Bound:

`withdrawnX <= totalLockedX * unlockedBps / 10000`

Controls:

- manager-only mutations
- non-reentrant withdrawals
- monotonic unlock bps
