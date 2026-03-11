#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PIN_V4_PERIPHERY="3779387e5d296f39df543d23524b050f89a62917"
PIN_V4_CORE="59d3ecf53afa9264a16bba0e38f4c5d2231f80bc"
PIN_OPENZEPPELIN="dbb6104ce834628e473d2173bbc9d47f81a9eec3"
PIN_FORGE_STD="0844d7e1fc5e60d77b68e469bff60265f236c398"

CHECK_ONLY="false"
if [[ "${1:-}" == "--check-only" ]]; then
  CHECK_ONLY="true"
fi

ensure_repo() {
  local dir="$1"
  local repo="$2"
  local ref="$3"

  if [[ ! -d "$dir/.git" ]]; then
    echo "Installing $repo@$ref into $dir"
    forge install "$repo@$ref"
  fi
}

expect_head() {
  local dir="$1"
  local expected="$2"
  local actual
  actual="$(git -C "$dir" rev-parse HEAD)"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $dir is at $actual but expected $expected"
    exit 1
  fi
}

if [[ "$CHECK_ONLY" != "true" ]]; then
  ensure_repo "lib/forge-std" "foundry-rs/forge-std" "$PIN_FORGE_STD"
  ensure_repo "lib/openzeppelin-contracts" "OpenZeppelin/openzeppelin-contracts" "$PIN_OPENZEPPELIN"
  ensure_repo "lib/v4-core" "Uniswap/v4-core" "$PIN_V4_CORE"
  ensure_repo "lib/v4-periphery" "Uniswap/v4-periphery" "$PIN_V4_PERIPHERY"
fi

if [[ "$CHECK_ONLY" != "true" && -f .gitmodules ]]; then
  git submodule update --init --recursive
fi

expect_head "lib/forge-std" "$PIN_FORGE_STD"
expect_head "lib/openzeppelin-contracts" "$PIN_OPENZEPPELIN"
expect_head "lib/v4-core" "$PIN_V4_CORE"
expect_head "lib/v4-periphery" "$PIN_V4_PERIPHERY"

if [[ -d "lib/v4-periphery/lib/v4-core/.git" ]]; then
  expect_head "lib/v4-periphery/lib/v4-core" "$PIN_V4_CORE"
fi

echo "Dependency pin verification passed."
echo "v4-periphery: $PIN_V4_PERIPHERY"
echo "v4-core:      $PIN_V4_CORE"
