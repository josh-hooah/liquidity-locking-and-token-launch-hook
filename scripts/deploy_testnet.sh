#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source "$ROOT_DIR/scripts/_load_env.sh"

RPC_URL="${UNICHAIN_SEPOLIA_RPC_URL:-${SEPOLIA_RPC_URL:-${BASE_SEPOLIA_RPC_URL:-${RPC_URL:-}}}}"
PRIVATE_KEY="${SEPOLIA_PRIVATE_KEY:-${PRIVATE_KEY:-}}"
EXPLORER_TX_BASE_URL="${EXPLORER_TX_BASE_URL:-https://sepolia.uniscan.xyz/tx/}"
POOL_MANAGER_ADDRESS="${POOL_MANAGER_ADDRESS:-}"
OWNER_ADDRESS="${OWNER_ADDRESS:-}"

if [[ -z "$RPC_URL" ]]; then
  echo "Set UNICHAIN_SEPOLIA_RPC_URL, SEPOLIA_RPC_URL, BASE_SEPOLIA_RPC_URL, or RPC_URL"
  exit 1
fi
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set SEPOLIA_PRIVATE_KEY or PRIVATE_KEY"
  exit 1
fi
export PRIVATE_KEY
if [[ -n "$POOL_MANAGER_ADDRESS" ]]; then
  export POOL_MANAGER_ADDRESS
fi
if [[ -n "$OWNER_ADDRESS" ]]; then
  export OWNER_ADDRESS
fi

forge script script/DeployLaunchSystem.s.sol:DeployLaunchSystem \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv

scripts/_print_broadcast_summary.sh "DeployLaunchSystem.s.sol" "$RPC_URL" "$EXPLORER_TX_BASE_URL"

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
RUN_FILE="broadcast/DeployLaunchSystem.s.sol/${CHAIN_ID}/run-latest.json"

if [[ -f "$RUN_FILE" && -f ".env" ]]; then
  LAUNCH_MANAGER_ADDRESS="$(jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "LaunchManager") | .contractAddress' "$RUN_FILE" | tail -n1)"
  LIQUIDITY_LOCK_VAULT_ADDRESS="$(jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "LiquidityLockVault") | .contractAddress' "$RUN_FILE" | tail -n1)"
  LAUNCH_LOCK_HOOK_ADDRESS="$(jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "LaunchLockHook") | .contractAddress' "$RUN_FILE" | tail -n1)"
  HOOK_DEPLOYER_ADDRESS="$(jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "HookDeployer") | .contractAddress' "$RUN_FILE" | tail -n1)"

  if [[ -z "$LAUNCH_LOCK_HOOK_ADDRESS" || "$LAUNCH_LOCK_HOOK_ADDRESS" == "null" ]]; then
    if [[ -n "$LAUNCH_MANAGER_ADDRESS" && "$LAUNCH_MANAGER_ADDRESS" != "null" ]]; then
      LAUNCH_LOCK_HOOK_ADDRESS="$(cast call --rpc-url "$RPC_URL" "$LAUNCH_MANAGER_ADDRESS" "launchHook()(address)" 2>/dev/null || true)"
    fi
  fi

  upsert_env() {
    local key="$1"
    local value="$2"

    if [[ -z "$value" || "$value" == "null" ]]; then
      return
    fi

    if grep -q "^${key}=" .env; then
      sed -i.bak "s|^${key}=.*|${key}=${value}|" .env
    else
      echo "${key}=${value}" >> .env
    fi
  }

  upsert_env "LAUNCH_MANAGER_ADDRESS" "$LAUNCH_MANAGER_ADDRESS"
  upsert_env "LIQUIDITY_LOCK_VAULT_ADDRESS" "$LIQUIDITY_LOCK_VAULT_ADDRESS"
  upsert_env "LAUNCH_LOCK_HOOK_ADDRESS" "$LAUNCH_LOCK_HOOK_ADDRESS"
  upsert_env "HOOK_DEPLOYER_ADDRESS" "$HOOK_DEPLOYER_ADDRESS"

  rm -f .env.bak

  echo
  echo "Stored deployment addresses in .env:"
  echo "- LAUNCH_MANAGER_ADDRESS=${LAUNCH_MANAGER_ADDRESS}"
  echo "- LIQUIDITY_LOCK_VAULT_ADDRESS=${LIQUIDITY_LOCK_VAULT_ADDRESS}"
  echo "- LAUNCH_LOCK_HOOK_ADDRESS=${LAUNCH_LOCK_HOOK_ADDRESS}"
  echo "- HOOK_DEPLOYER_ADDRESS=${HOOK_DEPLOYER_ADDRESS}"
fi
