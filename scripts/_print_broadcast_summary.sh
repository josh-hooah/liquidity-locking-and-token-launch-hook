#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <script_file> <rpc_url> <explorer_tx_base_url_or_empty>"
  exit 1
fi

SCRIPT_FILE="$1"
RPC_URL="$2"
EXPLORER_TX_BASE_URL="$3"

CHAIN_ID="$(cast chain-id --rpc-url "$RPC_URL")"
RUN_FILE="broadcast/${SCRIPT_FILE}/${CHAIN_ID}/run-latest.json"

if [[ ! -f "$RUN_FILE" ]]; then
  echo "No broadcast run file found at $RUN_FILE"
  exit 1
fi

echo "Broadcast file: $RUN_FILE"

echo "Transactions:"
jq -r '.transactions[] | [.transactionType, .contractName, .contractAddress, .hash] | @tsv' "$RUN_FILE" | while IFS=$'\t' read -r txType contractName contractAddress hash; do
  if [[ -n "$EXPLORER_TX_BASE_URL" ]]; then
    txUrl="${EXPLORER_TX_BASE_URL}${hash}"
  else
    txUrl="TBD ${hash}"
  fi
  echo "- type=${txType} contract=${contractName} address=${contractAddress} hash=${hash} explorer=${txUrl}"
done
