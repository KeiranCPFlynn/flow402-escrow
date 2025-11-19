#!/usr/bin/env bash
set -euo pipefail

ENV_FILE=${ENV_FILE:-.env}
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
fi

if ! command -v anvil >/dev/null 2>&1; then
  echo "❌ anvil (Foundry) is not installed or not on PATH." >&2
  exit 1
fi

if [[ -z "${BASE_SEPOLIA_RPC_URL:-}" ]]; then
  echo "❌ BASE_SEPOLIA_RPC_URL must be set to a real RPC endpoint (Alchemy, Infura, etc.)." >&2
  exit 1
fi

echo "→ Starting Base Sepolia fork…"

CHAIN_ID=${BASE_FORK_CHAIN_ID:-84532}
PORT=${BASE_FORK_PORT:-8545}
HOST=${BASE_FORK_HOST:-127.0.0.1}
BLOCK_TIME=${BASE_FORK_BLOCK_TIME:-1}
GAS_LIMIT=${BASE_FORK_GAS_LIMIT:-30000000}
BALANCE_WEI=${BASE_FORK_BALANCE_WEI:-10000000000000000000}
FORK_BLOCK_ARGS=()

if [[ -n "${BASE_FORK_BLOCK_NUMBER:-}" ]]; then
  FORK_BLOCK_ARGS=(--fork-block-number "$BASE_FORK_BLOCK_NUMBER")
fi

echo "RPC URL     : $BASE_SEPOLIA_RPC_URL"
echo "Host:Port   : $HOST:$PORT"
echo "Chain ID    : $CHAIN_ID"
if [[ ${#FORK_BLOCK_ARGS[@]} -gt 0 ]]; then
  echo "Fork Block  : $BASE_FORK_BLOCK_NUMBER"
else
  echo "Fork Block  : latest"
fi

ANVIL_ARGS=(
  --fork-url "$BASE_SEPOLIA_RPC_URL"
  --host "$HOST"
  --port "$PORT"
  --chain-id "$CHAIN_ID"
  --block-time "$BLOCK_TIME"
  --gas-limit "$GAS_LIMIT"
  --auto-impersonate
  --balance "$BALANCE_WEI"
)

if [[ ${#FORK_BLOCK_ARGS[@]} -gt 0 ]]; then
  ANVIL_ARGS+=("${FORK_BLOCK_ARGS[@]}")
fi

exec anvil "${ANVIL_ARGS[@]}"
