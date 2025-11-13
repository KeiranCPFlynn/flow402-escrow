#!/usr/bin/env bash
set -euo pipefail

echo "→ Flow402 Local Cycle starting…"

RPC_URL=${RPC_URL:-http://127.0.0.1:8545}
DEPLOYER_PK=${DEPLOYER_PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
DEPLOYER_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
GATEWAY_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
VENDOR_ADDRESS=0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC

echo "RPC_URL         = $RPC_URL"
echo "DEPLOYER_ADDR   = $DEPLOYER_ADDRESS"
echo "GATEWAY_ADDR    = $GATEWAY_ADDRESS"
echo "VENDOR_ADDR     = $VENDOR_ADDRESS"

echo "→ Deploying MockUSDC…"
USDC_ADDRESS=$(forge create src/mocks/MockUSDC.sol:MockUSDC \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --broadcast \
  | grep "Deployed to" | awk '{print $3}')

echo "USDC_ADDRESS    = $USDC_ADDRESS"

echo "→ Deploying Flow402Treasury via script…"
forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC_URL" \
  --private-key "$DEPLOYER_PK" \
  --broadcast -vvvv


echo "→ Cycle done!"
