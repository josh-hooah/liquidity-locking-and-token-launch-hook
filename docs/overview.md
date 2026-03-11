# Overview

Liquidity Locking & Token Launch Hook is a deterministic launch primitive for Uniswap v4 launch pools.

It combines:

- launch-window anti-snipe controls
- policy-driven progressive liquidity unlocks
- manager/vault separation for minimal hook complexity

Primary goals:

- safer early market formation
- transparent unlock criteria
- permissionless progression without keepers
