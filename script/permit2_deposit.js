// -------------------------------------------------------------
// Load environment (MATCHES YOUR .env EXACTLY)
// -------------------------------------------------------------
require("dotenv").config();
const { ethers } = require("ethers");
const fs = require("fs");

// Load vars from .env
const {
    DEPLOYER_PK,
    GATEWAY_PK,
    TREASURY_ADDRESS,
    USDC_ADDRESS,
    RPC_URL,
} = process.env;

const PERMIT2 =
    process.env.PERMIT2 || "0x000000000022D473030F116dDEE9F6B43aC78BA3";

// Validate env vars before doing anything else
if (!DEPLOYER_PK || !GATEWAY_PK || !TREASURY_ADDRESS || !USDC_ADDRESS) {
    console.error("\n❌ Missing environment variables. You must export:");
    console.error("   DEPLOYER_PK, GATEWAY_PK, TREASURY_ADDRESS, USDC_ADDRESS\n");
    process.exit(1);
}

// Provider MUST be created before wallets
const provider = new ethers.providers.JsonRpcProvider(
    RPC_URL || "http://127.0.0.1:8545"
);

// Wallets
const user = new ethers.Wallet(DEPLOYER_PK, provider);
const relayer = new ethers.Wallet(GATEWAY_PK, provider);

// Normalised names for rest of script
const TREASURY = TREASURY_ADDRESS;
const USDC = USDC_ADDRESS;
