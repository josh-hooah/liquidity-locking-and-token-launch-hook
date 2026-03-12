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
echo "Chain ID: $CHAIN_ID"

echo "Transactions:"
jq -r '
  .transactions as $txs
  | .receipts as $receipts
  | range(0; ($txs | length)) as $i
  | [
      ($i + 1 | tostring),
      ($txs[$i].transactionType // "-"),
      ($txs[$i].contractName // "-"),
      ($txs[$i].function // "-"),
      ($txs[$i].contractAddress // "-"),
      ($txs[$i].hash // "-"),
      ($receipts[$i].status // "0x0"),
      ($receipts[$i].gasUsed // "0x0")
    ]
  | @tsv
' "$RUN_FILE" | while IFS=$'\t' read -r idx txType contractName functionName contractAddress hash status gasUsed; do
  if [[ -n "$EXPLORER_TX_BASE_URL" ]]; then
    txUrl="${EXPLORER_TX_BASE_URL}${hash}"
  else
    txUrl="TBD ${hash}"
  fi

  statusLabel="FAILED"
  if [[ "$status" == "0x1" ]]; then
    statusLabel="SUCCESS"
  fi

  echo "- [${idx}] status=${statusLabel} type=${txType} contract=${contractName} function=${functionName} address=${contractAddress} gasUsed=${gasUsed} hash=${hash} explorer=${txUrl}"
done
