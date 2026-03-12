#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/_load_env.sh"

RPC_URL="${UNICHAIN_SEPOLIA_RPC_URL:-${SEPOLIA_RPC_URL:-${BASE_SEPOLIA_RPC_URL:-${RPC_URL:-}}}}"
PRIVATE_KEY="${SEPOLIA_PRIVATE_KEY:-${PRIVATE_KEY:-}}"
EXPLORER_TX_BASE_URL="${EXPLORER_TX_BASE_URL:-https://sepolia.uniscan.xyz/tx/}"
POOL_MANAGER_ADDRESS="${POOL_MANAGER_ADDRESS:-}"
LAUNCH_MANAGER_ADDRESS="${LAUNCH_MANAGER_ADDRESS:-}"
LIQUIDITY_LOCK_VAULT_ADDRESS="${LIQUIDITY_LOCK_VAULT_ADDRESS:-}"
LAUNCH_LOCK_HOOK_ADDRESS="${LAUNCH_LOCK_HOOK_ADDRESS:-}"

if [[ -z "$RPC_URL" ]]; then
  echo "Set UNICHAIN_SEPOLIA_RPC_URL, SEPOLIA_RPC_URL, BASE_SEPOLIA_RPC_URL, or RPC_URL"
  exit 1
fi
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set SEPOLIA_PRIVATE_KEY or PRIVATE_KEY"
  exit 1
fi
export PRIVATE_KEY

if [[ -z "$POOL_MANAGER_ADDRESS" ]]; then
  echo "Set POOL_MANAGER_ADDRESS in .env for Unichain Sepolia"
  exit 1
fi

if [[ -z "$LAUNCH_MANAGER_ADDRESS" || -z "$LIQUIDITY_LOCK_VAULT_ADDRESS" || -z "$LAUNCH_LOCK_HOOK_ADDRESS" ]]; then
  echo "Deployment addresses missing in .env; deploying launch system first..."
  "$ROOT_DIR/scripts/deploy_testnet.sh"
  source "$ROOT_DIR/scripts/_load_env.sh"
  LAUNCH_MANAGER_ADDRESS="${LAUNCH_MANAGER_ADDRESS:-}"
  LIQUIDITY_LOCK_VAULT_ADDRESS="${LIQUIDITY_LOCK_VAULT_ADDRESS:-}"
  LAUNCH_LOCK_HOOK_ADDRESS="${LAUNCH_LOCK_HOOK_ADDRESS:-}"
fi

if [[ -z "$LAUNCH_MANAGER_ADDRESS" || -z "$LIQUIDITY_LOCK_VAULT_ADDRESS" || -z "$LAUNCH_LOCK_HOOK_ADDRESS" ]]; then
  echo "Deployment addresses are still missing after deploy_testnet.sh"
  exit 1
fi

export POOL_MANAGER_ADDRESS
export LAUNCH_MANAGER_ADDRESS
export LIQUIDITY_LOCK_VAULT_ADDRESS
export LAUNCH_LOCK_HOOK_ADDRESS
export USE_DEPLOYED_SYSTEM=true

forge script script/DemoLaunchLifecycle.s.sol:DemoLaunchLifecycle \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv

scripts/_print_broadcast_summary.sh "DemoLaunchLifecycle.s.sol" "$RPC_URL" "$EXPLORER_TX_BASE_URL"
