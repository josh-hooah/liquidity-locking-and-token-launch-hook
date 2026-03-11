#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RPC_URL="${RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"
export PRIVATE_KEY

ANVIL_STARTED="false"
if ! cast chain-id --rpc-url "$RPC_URL" >/dev/null 2>&1; then
  echo "Starting local anvil at 127.0.0.1:8545"
  anvil --host 127.0.0.1 --port 8545 --chain-id 31337 >/tmp/liquidity-lock-anvil.log 2>&1 &
  ANVIL_PID=$!
  ANVIL_STARTED="true"
  trap 'if [[ "$ANVIL_STARTED" == "true" ]]; then kill -9 "$ANVIL_PID" >/dev/null 2>&1 || true; fi' EXIT
  sleep 1
fi

forge script script/DemoLaunchLifecycle.s.sol:DemoLaunchLifecycle \
  --rpc-url "$RPC_URL" \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  -vvvv

scripts/_print_broadcast_summary.sh "DemoLaunchLifecycle.s.sol" "$RPC_URL" ""
