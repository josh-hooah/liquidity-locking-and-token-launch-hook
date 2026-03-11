#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/demo_local.sh | tee /tmp/demo-all.log

echo "Judge summary:"
rg "DEMO_DEPLOYER|DEMO_POOL_MANAGER|DEMO_VAULT|DEMO_LAUNCH_MANAGER|DEMO_HOOK|DEMO_ALLOWED_SWAPS|DEMO_BLOCKED_SWAPS|DEMO_UNLOCKED_BPS|DEMO_WITHDRAWN_0|DEMO_WITHDRAWN_1|DEMO_REMAINING_UNLOCKABLE_0|DEMO_REMAINING_UNLOCKABLE_1" /tmp/demo-all.log || true
