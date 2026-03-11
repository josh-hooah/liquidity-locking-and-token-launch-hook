# Deployment

## Local
```bash
make deploy-local
```

## Base Sepolia (preferred)
```bash
export PRIVATE_KEY=0x...
export BASE_SEPOLIA_RPC_URL=https://...
make deploy-testnet
```

Scripts print contract addresses and tx hashes from broadcast JSON.
