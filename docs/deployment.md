# Deployment

## Local
```bash
make deploy-local
```

## Unichain Sepolia
```bash
cp .env.example .env
# fill signer + rpc values
make deploy-testnet
```

`scripts/deploy_testnet.sh` behavior:

- loads `.env`
- reuses `POOL_MANAGER_ADDRESS` from Unichain Sepolia infra
- deploys `LiquidityLockVault`, `LaunchManager`, `HookDeployer`, and `LaunchLockHook`
- sets manager + hook wiring
- prints full tx hash/explorer URL summary
- writes deployed addresses back into `.env`:
  - `LAUNCH_MANAGER_ADDRESS`
  - `LIQUIDITY_LOCK_VAULT_ADDRESS`
  - `LAUNCH_LOCK_HOOK_ADDRESS`
  - `HOOK_DEPLOYER_ADDRESS`

Reactive network integration is not part of this repository; no Reactive RPC/private-key environment variables are required for deployment or demo flows.

Latest Unichain Sepolia deployment:

- `POOL_MANAGER_ADDRESS=0x00b036b58a818b1bc34d502d3fe730db729e62ac`
- `LIQUIDITY_LOCK_VAULT_ADDRESS=0xb664e46c230951da4389e195188aa4203fa76af0`
- `LAUNCH_MANAGER_ADDRESS=0x53edcb5facceede8a1eac2237daebf7fc983a574`
- `HOOK_DEPLOYER_ADDRESS=0x3726b4eaf838fcff2096461a920fa277af313317`
- `LAUNCH_LOCK_HOOK_ADDRESS=0x8165120E7C04bD5F52dF16d90365f87C1DFe80c0`
