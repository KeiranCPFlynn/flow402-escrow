#!/usr/bin/env bash
set -euo pipefail

echo "→ Flow402 Local Cycle starting…"

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
DEPLOYER_PK=${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
FLOW_CHAIN_ID=${FLOW_CHAIN_ID:-31337}
FLOW402_CREDITS_DIR=${FLOW402_CREDITS_DIR:-../flow402-credits}
CONTRACTS_DIR=${CONTRACTS_DIR:-$FLOW402_CREDITS_DIR/packages/contracts}
DEPLOYMENT_FILENAME=${DEPLOYMENT_FILENAME:-deployment.local.json}
OUTPUT_FILE=${OUTPUT_FILE:-$CONTRACTS_DIR/$DEPLOYMENT_FILENAME}
FLOW_ENV_FILE=${FLOW_ENV_FILE:-$FLOW402_CREDITS_DIR/apps/web/.env.local}
ENV_USDC_KEY=${ENV_USDC_KEY:-NEXT_PUBLIC_USDC_ADDRESS}
ENV_TREASURY_KEY=${ENV_TREASURY_KEY:-NEXT_PUBLIC_TREASURY_ADDRESS}
ENV_VENDOR_KEY=${ENV_VENDOR_KEY:-NEXT_PUBLIC_VENDOR_ADDRESS}
ENV_RPC_KEY=${ENV_RPC_KEY:-NEXT_PUBLIC_RPC_URL}

# ------------------------------------------------
# Anvil accounts used by Flow402
# ------------------------------------------------
DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
GATEWAY_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
VENDOR_ADDRESS=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

# User test wallet — ANVIL ACCOUNT #9
TEST_WALLET_ADDRESS=0xa0ee7a142d267c1f36714e4a8f75612f20a79720

# Mint 1,000 USDC (6 decimals)
MINT_AMOUNT=1000000000

echo "RPC_URL         = $RPC_URL"
echo "DEPLOYER_ADDR   = $DEPLOYER_ADDRESS"
echo "GATEWAY_ADDR    = $GATEWAY_ADDRESS"
echo "VENDOR_ADDR     = $VENDOR_ADDRESS"
echo "TEST_WALLET     = $TEST_WALLET_ADDRESS"

# ------------------------------------------------
# 1. Deploy MockUSDC
# ------------------------------------------------
echo "→ Deploying MockUSDC…"

USDC_ADDRESS=$(forge create src/mocks/MockUSDC.sol:MockUSDC \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --broadcast \
  | grep "Deployed to" | awk '{print $3}')

if [[ -z "${USDC_ADDRESS:-}" ]]; then
  echo "❌ Failed to determine USDC address" >&2
  exit 1
fi

echo "USDC_ADDRESS    = $USDC_ADDRESS"

# ------------------------------------------------
# 2. Deploy Treasury/Escrow
# ------------------------------------------------
echo "→ Deploying Flow402Treasury via script…"
TREASURY_LOG=$(mktemp)

# Export variables so forge script can read them
export USDC_ADDRESS="$USDC_ADDRESS"
export GATEWAY_ADDRESS="$GATEWAY_ADDRESS"
export DEPLOYER_PK="$DEPLOYER_PK"

forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --broadcast -vvvv | tee "$TREASURY_LOG"

TREASURY_ADDRESS=$(grep -E "Treasury deployed at:|Contract Address:" "$TREASURY_LOG" | awk '{print $NF}' | tail -n1)
rm -f "$TREASURY_LOG"

if [[ -z "${TREASURY_ADDRESS:-}" ]]; then
  echo "❌ Failed to determine Treasury address" >&2
  exit 1
fi

echo "TREASURY_ADDRESS = $TREASURY_ADDRESS"

# ------------------------------------------------
# 3. Write deployment artifact (credits repo)
# ------------------------------------------------
mkdir -p "$CONTRACTS_DIR"

cat <<EOF > "$OUTPUT_FILE"
{
  "treasury": "$TREASURY_ADDRESS",
  "usdc": "$USDC_ADDRESS",
  "vendor": "$VENDOR_ADDRESS",
  "chainId": $FLOW_CHAIN_ID,
  "rpcUrl": "$RPC_URL"
}
EOF

echo "→ Wrote deployment artifact to $OUTPUT_FILE"

# ------------------------------------------------
# 4. Update env file for apps/web
# ------------------------------------------------
echo "→ Updating $FLOW_ENV_FILE"

mkdir -p "$(dirname "$FLOW_ENV_FILE")"
touch "$FLOW_ENV_FILE"

update_env_var() {
  local key="$1"
  local value="$2"

  if grep -q "^$key=" "$FLOW_ENV_FILE"; then
    sed -i.bak "s|^$key=.*|$key=$value|" "$FLOW_ENV_FILE"
  else
    echo "$key=$value" >> "$FLOW_ENV_FILE"
  fi
}

update_env_var "$ENV_USDC_KEY" "$USDC_ADDRESS"
update_env_var "$ENV_TREASURY_KEY" "$TREASURY_ADDRESS"
update_env_var "$ENV_VENDOR_KEY" "$VENDOR_ADDRESS"
update_env_var "$ENV_RPC_KEY" "$RPC_URL"

rm -f "$FLOW_ENV_FILE.bak"

echo "→ Updated .env.local with new contract addresses"

# ------------------------------------------------
# 5. Auto-mint USDC to Gateway, Vendor, TestWallet
# ------------------------------------------------
echo "→ Minting USDC to Gateway, Vendor, and Test wallet…"

AUTO_MINT_TARGETS=(
  "$GATEWAY_ADDRESS"
  "$VENDOR_ADDRESS"
  "$TEST_WALLET_ADDRESS"
)

for TARGET in "${AUTO_MINT_TARGETS[@]}"; do
  echo "  - Minting $MINT_AMOUNT to $TARGET"

  cast send "$USDC_ADDRESS" \
    "mint(address,uint256)" \
    "$TARGET" "$MINT_AMOUNT" \
    --rpc-url "$RPC_URL" \
    --private-key "$DEPLOYER_PK" \
    >/dev/null
done

echo "→ Auto-mint complete!"

# ------------------------------------------------
# OPTIONAL: Auto-send ETH to test wallet
# (Commented out because Anvil built-in accounts
# already start with 10,000 ETH)
# ------------------------------------------------
# echo "→ Sending 10 ETH to test wallet…"
# cast send "$TEST_WALLET_ADDRESS" \
#   --value 10ether \
#   --rpc-url "$RPC_URL" \
#   --private-key "$DEPLOYER_PK" >/dev/null
# echo "→ ETH funding complete!"

# ------------------------------------------------
# 6. Print balances
# ------------------------------------------------
echo "→ Checking balances…"

check_balance () {
  local addr="$1"
  local label="$2"
  local bal

  bal=$(cast call "$USDC_ADDRESS" \
    "balanceOf(address)(uint256)" "$addr" \
    --rpc-url "$RPC_URL")

  echo "  $label balance: $bal (raw, divide by 1e6 for USDC)"
}

check_balance "$GATEWAY_ADDRESS"  "Gateway"
check_balance "$VENDOR_ADDRESS"   "Vendor"
check_balance "$TEST_WALLET_ADDRESS" "User Wallet (#9)"

echo "→ Balance check complete!"

# ------------------------------------------------
# Done
# ------------------------------------------------
echo "→ Local cycle complete!"
echo "USDC_ADDRESS     = $USDC_ADDRESS"
echo "TREASURY_ADDRESS = $TREASURY_ADDRESS"
