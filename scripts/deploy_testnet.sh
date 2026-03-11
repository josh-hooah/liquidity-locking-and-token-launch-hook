#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPC_URL="${BASE_SEPOLIA_RPC_URL:-${RPC_URL:-}}"
PRIVATE_KEY="${PRIVATE_KEY:-}"
EXPLORER_TX_BASE_URL="${EXPLORER_TX_BASE_URL:-https://sepolia.basescan.org/tx/}"

if [[ -z "$RPC_URL" ]]; then
  echo "Set BASE_SEPOLIA_RPC_URL or RPC_URL"
  exit 1
fi
if [[ -z "$PRIVATE_KEY" ]]; then
  echo "Set PRIVATE_KEY"
  exit 1
fi
export PRIVATE_KEY

forge script script/DeployLaunchSystem.s.sol:DeployLaunchSystem \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv

scripts/_print_broadcast_summary.sh "DeployLaunchSystem.s.sol" "$RPC_URL" "$EXPLORER_TX_BASE_URL"
