#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/demo_local.sh | tee /tmp/demo-unlock.log

echo "Unlock summary:"
rg "DEMO_UNLOCKED_BPS|DEMO_WITHDRAWN_0|DEMO_WITHDRAWN_1|DEMO_REMAINING_UNLOCKABLE_0|DEMO_REMAINING_UNLOCKABLE_1" /tmp/demo-unlock.log || true
