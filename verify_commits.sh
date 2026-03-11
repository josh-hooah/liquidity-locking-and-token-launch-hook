#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-68}"
COUNT="$(git rev-list --count HEAD)"

if [[ "$COUNT" != "$TARGET" ]]; then
  echo "Commit count mismatch: expected=$TARGET actual=$COUNT"
  exit 1
fi

echo "Commit count verified: $COUNT"
