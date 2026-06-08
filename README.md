# FlowPass

FlowPass is a local MVP for a Uniswap v4-style dynamic fee hook that gives prepaid
membership pass holders discounted swap fees for a fixed amount of future USD volume.

The project now includes a local Foundry test suite, a real Uniswap v4 hook
adapter, a custom exact-input router, a broadcasted Unichain Sepolia mock-token
demo, and a read-only dashboard for explaining the mechanism.

The MVP focuses on the core mechanism:

- single pass tier
- USDC pass payment
- one wallet per pass
- exact-input pass usage only
- full quota coverage required for discount
- quota deducted after actual executed volume
- upfront revenue split into LP reserve and treasury reserve
- trusted router required for pass-enabled swaps
- real Uniswap v4 `IHooks.beforeSwap` / `afterSwap` adapter now included
- minimal exact-input `FlowPassRouter` for local PoolManager integration
- router-level `amountOutMinimum` slippage protection
- pass purchase and quota consumption restricted to the current FlowPass pool key

## Local Test

```bash
forge test
```

Build all contracts and deployment scripts:

```bash
forge build
```

If Foundry is not installed yet, a lightweight Solidity compile check is available:

```bash
npm install
npm run compile
```

If Solidity tooling is unavailable, the zero-dependency local behavior demo can
still be run with Node:

```bash
node tools/demo-flowpass.js
```

## Dashboard

Open the read-only dashboard:

```bash
npm run dashboard
```

Then visit:

```text
http://127.0.0.1:8080
```

The dashboard shows the testnet deployment, pass lifecycle, quota state, and a
parameter sandbox for pass price, quota, discount fee, and LP/treasury split.

## Unichain Sepolia Demo

The mock-token demo was broadcast successfully on Unichain Sepolia.

| Item | Address |
|---|---|
| FlowPassV4Hook | `0xEfEf9F8aC2B1fEC9b173Ae3530Cdeb1407BC80C0` |
| FlowPassRouter | `0xD22505dD65B985FBf47c2030a6421536fe0C3159` |
| Mock token A | `0xd119Da24acdc69190C0a12c1CCD64115c38DE6ac` |
| Mock token B | `0xf06219433b255A42667EFD5F0177194Fa6Dbe0f9` |

Pool id:

```text
0x6770d05ee2d5efb0a94ea7f27c5212b580b17c1d045c52b3505797721d9c9acb
```

Final demo swap transaction:

```text
0xdf2970c1b82d94ebb29b0fb9793d4d6bfae0fba8f8f497a0ec251256a9b6f09d
```

See `TESTNET_DEPLOYMENT.md` for the full deployment log and verification commands.

Verify the deployed demo with read-only RPC calls:

```bash
npm run verify:testnet
```

To use a different RPC endpoint:

```bash
RPC_URL=<UNICHAIN_SEPOLIA_RPC_URL> npm run verify:testnet
```

## Current MVP Parameters

| Parameter | Value |
|---|---|
| Base fee | `100` pips = 1 bp |
| Discount fee | `50` pips = 0.5 bp candidate |
| Pass price | `300 USDC` |
| Quota | `10,000,000 USD` volume |
| Duration | `7 days` |
| Revenue split | `70% LP reserve / 30% treasury reserve` |

These economic values are placeholders for local demo. The next step is to calibrate
them from historical USDC/USDT0 Unichain swap data.

## Main Files

| File | Purpose |
|---|---|
| `src/FlowPassHook.sol` | Core MVP pass logic and hook-shaped swap accounting. |
| `src/FlowPassV4Hook.sol` | Real Uniswap v4 `IHooks` adapter for `beforeSwap` / `afterSwap`. |
| `src/FlowPassRouter.sol` | Minimal exact-input ERC20 router that forwards trader identity in `hookData`. |
| `test/FlowPassHook.t.sol` | Foundry tests for key pass and swap paths. |
| `test/FlowPassV4Hook.t.sol` | Foundry tests for the real v4 hook signatures and fee override behavior. |
| `test/FlowPassV4PoolManager.t.sol` | Local PoolManager integration test with mined hook flags, `FlowPassRouter`, and real v4 swap lifecycle. |
| `test/mocks/MockFlowPassRouter.sol` | Trusted router used to pass trader identity. |
| `test/mocks/MockERC20.sol` | Mock USDC used for local testing. |
| `script/DeployLocalDemo.s.sol` | Local mock deployment helper. |
| `script/DeployFlowPassHook.s.sol` | Minimal hook deploy helper for a real payment token. |
| `script/DeployUnichainSepoliaHook.s.sol` | Unichain Sepolia hook + router deployment script. |
| `script/DeployUnichainSepoliaMockDemo.s.sol` | Unichain Sepolia mock-token end-to-end demo script. |
| `frontend/index.html` | Read-only visualization dashboard for demo and parameter calibration. |
| `docs/FINAL_SUBMISSION.md` | Draft final Hookathon submission content. |
| `docs/DATA_AND_PRICING_WORKFLOW.md` | Data workflow for production pass parameter calibration. |
| `TESTNET_DEPLOYMENT.md` | Testnet deployment commands and required inputs. |
| `tools/demo-flowpass.js` | Zero-dependency behavior demo when Solidity tooling is unavailable. |
| `tools/verify-testnet.sh` | Read-only Unichain Sepolia verification script. |

## Current Integration Status

The project has two layers:

- `FlowPassHook.sol`: hook-shaped business logic MVP with local mocks.
- `FlowPassV4Hook.sol`: real v4 `IHooks` adapter that returns per-swap LP fee overrides in `beforeSwap` and deducts quota in `afterSwap`.
- `FlowPassRouter.sol`: minimal router that performs PoolManager `unlock -> swap -> settle/take` and passes `abi.encode(trader)` to the hook.

The v4 adapter includes a local PoolManager integration test with a CREATE2-mined hook
address for `BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG`. The test now swaps through the
project router instead of Uniswap's test-only swap router.

The v4 adapter intentionally rejects static-fee pools. FlowPass fee discounts depend
on Uniswap v4 dynamic LP fee overrides, so a static-fee pool would otherwise ignore
the returned discount fee while the hook could still consume quota.

The mock-token path is now deployed on Unichain Sepolia. Production deployment
still requires final USDC/USDT0 token choices, treasury setup, pass pricing,
LP distribution policy, router/quoter integration, and audit work. See
`TESTNET_DEPLOYMENT.md` and `docs/DATA_AND_PRICING_WORKFLOW.md`.
