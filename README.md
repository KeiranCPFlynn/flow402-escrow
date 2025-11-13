flow402-escrow
================

Flow402Treasury is the on-chain escrow that custodially holds user USDC deposits, applies protocol fees, enforces per-user spending limits, and pays vendors once the Flow402 gateway settles batches. Funds only move between users, vendors, and protocol fee recipients inside the contract – no custodial keys.

1. Purpose
----------

- Users pre-fund the treasury with USDC (standard `transferFrom`, EIP-2612 permit, or Permit2 signature-transfer).  
- A configurable protocol fee (capped at **500 bps / 5%**) is skimmed upfront and accounted separately.  
- Each user chooses a spending limit; the gateway can only settle vendors up to that limit from the user’s balance.  
- Vendors withdraw their pending balances directly; users can also withdraw unused deposits.  
- Treasury owner (Flow402) can rotate the gateway, pause settlements, and withdraw accumulated protocol fees—nothing else.  
- Non-upgradeable, minimal surface area for easier audits.

2. Contract Spec (Flow402Treasury)
----------------------------------

**State**

- `IERC20 public immutable usdc`
- `address public gateway`
- `uint96 public feeBps` (default 100 bps, capped at 500 bps)
- `address public constant PERMIT2`
- `bool public settlementsPaused`
- `mapping(address => uint256) public userDeposits`
- `mapping(address => uint256) public userSpendingLimit`
- `mapping(address => uint256) public vendorPending`
- `uint256 public protocolFees`

**Key Functions**

| Function | Notes |
| --- | --- |
| `deposit(amount, spendingLimit)` | Pulls USDC via `transferFrom`, credits user net of fee. |
| `depositWithPermit(user, amount, spendingLimit, deadline, v, r, s)` | EIP-2612 path for signature-only approvals. |
| `depositWithPermit2(user, amount, spendingLimit, permit, details, signature)` | Permit2 signature transfer (one popup UX). |
| `setSpendingLimit(newLimit)` | User-managed kill-switch; limits per-settlement spend. |
| `batchSettle(users, vendors, amounts)` | Gateway-only, when not paused; moves balances from users to vendor pending. |
| `withdrawUser(amount)` / `withdrawVendor(amount)` | Non-reentrant withdrawals of unused or earned funds. |
| `withdrawProtocolFees(amount)` | Owner-only, transfers accrued protocol fees. |
| `setGateway`, `setSettlementsPaused`, `setFeeBps` | Admin levers (fee change enforces cap). |
| `totalReserves()` / `canUserSpend(user, amount)` | View helpers for integrations. |

Events: `UserDeposit`, `SpendingLimitUpdated`, `Settlement`, `UserWithdrawal`, `VendorWithdrawal`, `ProtocolFeeWithdrawal`, `GatewayUpdated`, `SettlementsPausedUpdated`, `FeeUpdated`.

3. Security Requirements
------------------------

- Re-entrancy guarded withdrawals + Permit2 entry.
- Fee guard enforced on-chain (`MAX_FEE_BPS = 500`).
- SafeERC20 interactions for all transfers.
- Batch settlement restricted to current `gateway`.
- Settlements can be paused without blocking withdrawals.
- Comprehensive Foundry tests cover deposits (all paths), settlement limits, withdrawals, admin controls, and failure cases.

4. Deployment
-------------

Environment variables (works for Base Sepolia and any other network):

```
USDC_ADDRESS=<deployed USDC token>
GATEWAY_ADDRESS=<off-chain settlement agent wallet>
FEE_BPS=100                       # example: 1%
PRIVATE_KEY=<deployer private key>
RPC_URL=<rpc endpoint>
GIT_COMMIT=<git sha used for this deploy>
```

Deploy + write `deployments/base-sepolia.json`:

```
forge script script/Deploy.s.sol \ 
  --rpc-url $RPC_URL \
  --broadcast
```

After deploy:

1. Copy `dist/abi/Flow402Treasury.json` (generated via `forge build && jq '{abi: .abi}' ...`) into the Flow402 web/SDK repo.  
2. Update the monorepo `.env` with the deployed address (Base Sepolia or other chain).  
3. Commit the refreshed `deployments/base-sepolia.json` so downstream apps track the live address, chainId, block number, and git commit used.

5. Local Testing & Workflows
----------------------------

- **Automated tests**: `forge test` (covers deposit, permit, permit2, batch settlement, withdrawals, admin guards, and failure modes).  
- **Custom scenarios**: run `anvil`, deploy a mock USDC + Flow402Treasury pair (or fork Base Sepolia) and exercise deposits via wallet/SDK by pointing `USDC_ADDRESS` at your local token and reusing the deploy script.  
- **Coverage / debug**: `forge test -vvv --match-test <name>` or `forge coverage` as needed.

6. Integration Boundary
-----------------------

The Flow402 web/SDK stack should:

- Import the ABI from `dist/abi/Flow402Treasury.json`.
- Use Permit2 for the single-popup UX (or fallback to legacy permit/approve).  
- Call `depositWithPermit2` (preferred) or `depositWithPermit` / `deposit`.  
- Display/allow user-managed spending limits via `setSpendingLimit`.  
- Gateway automation calls `batchSettle` with bounded batches.  
- Vendors withdraw themselves via `withdrawVendor`.  
- Monitor events `UserDeposit` and `Settlement` for accounting.

7. Repo Structure
-----------------

```
flow402-escrow/
├─ src/
│  ├─ Flow402Treasury.sol
│  └─ interfaces/
│     ├─ IERC20Permit.sol
│     └─ IPermit2.sol
├─ script/
│  └─ Deploy.s.sol
├─ test/
│  ├─ Flow402Treasury.t.sol
│  └─ mocks/MockPermit2.sol
├─ dist/abi/Flow402Treasury.json
├─ deployments/base-sepolia.json
├─ package.json
├─ foundry.toml
└─ README.md
```

8. Versioning & Release
-----------------------

- Tag `v*` → GitHub Actions workflow (`.github/workflows/publish-contracts.yml`) runs `forge build && forge test`, refreshes the trimmed ABI, bumps `package.json` to the tag’s version, and publishes `@flow402/contracts` containing the ABI + deployment JSONs.  
- Update `deployments/*.json` per network with each release.  
- v0.1.0: Flow402Treasury MVP (deposit paths, settlement, withdrawals, Permit2).

9. Definition of Done
---------------------

- Contract compiles and passes the entire Foundry suite.  
- Fee cap enforced at or below 5%.  
- Permit2 & permit deposit UX verified.  
- ABI exported + deployment metadata recorded.  
- CI publish workflow succeeds on release tags.  
- Manual deposit + batch settle + vendor withdraw confirmed on Base Sepolia prior to shipping frontend changes.

10. Useful Commands
-------------------

```
forge build
forge test
forge test -vv --match-test <pattern>
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast
jq '{abi: .abi}' out/Flow402Treasury.sol/Flow402Treasury.json > dist/abi/Flow402Treasury.json
```
