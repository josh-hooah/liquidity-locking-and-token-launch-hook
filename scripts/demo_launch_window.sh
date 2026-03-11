#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scripts/demo_local.sh | tee /tmp/demo-launch-window.log

echo "Launch-window summary:"
rg "DEMO_ALLOWED_SWAPS|DEMO_BLOCKED_SWAPS" /tmp/demo-launch-window.log || true
