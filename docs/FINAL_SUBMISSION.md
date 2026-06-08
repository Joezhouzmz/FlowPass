# FlowPass Final Submission Draft

## Project Name

FlowPass

## Short Description

FlowPass is a Uniswap v4 dynamic-fee hook that works like a prepaid trading
membership pass. A trader pays an upfront access fee to receive lower swap fees
for a fixed amount of future exact-input trading volume before the pass expires.

The hook stores each trader's remaining discounted volume and expiration time per
pool. During swaps, active pass holders receive a lower dynamic LP fee. After the
swap, the hook deducts actual input volume from the pass quota. When the pass is
expired or quota is insufficient, the trader falls back to the base fee.

## Demo Status

- Local Foundry tests: 31 passing tests.
- Testnet: broadcasted on Unichain Sepolia.
- Hook type: real Uniswap v4 `IHooks` adapter with `beforeSwap` and `afterSwap`.
- Router: custom exact-input `FlowPassRouter` that forwards trader identity in
  `hookData`.
- Frontend: read-only dashboard in `frontend/index.html`.

## Testnet Deployment

Network: Unichain Sepolia, chain id `1301`.

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

Key transactions:

| Action | Transaction hash |
|---|---|
| Deploy hook | `0xfbf8bd1ae03bf2fc93bf8bf2716ae02860bf679f96b4d437891ddd7ca5725b2a` |
| Deploy router | `0xc3f9f19df1eb1abddda668081913e95e09e6d95f9e374d80680d61925e7c4cc9` |
| Initialize pool | `0x25e3982751e62a462a05f06895fde6b7c4549d9a03de9a6bccc549300dd3aaf3` |
| Buy pass | `0x0a53275caa4add7cab4dfc1dc17750460fe70859a832e83159d6369fe3d0f38b` |
| Swap through FlowPassRouter | `0xdf2970c1b82d94ebb29b0fb9793d4d6bfae0fba8f8f497a0ec251256a9b6f09d` |

## How To Run

Run the Solidity test suite:

```bash
forge test
```

Run the lightweight behavior demo:

```bash
node tools/demo-flowpass.js
```

Open the dashboard:

```bash
npm run dashboard
```

Then open:

```text
http://127.0.0.1:8080
```

Verify the Unichain Sepolia deployment with read-only RPC calls:

```bash
npm run verify:testnet
```

## What The Demo Proves

1. A trader can buy a pass for a FlowPass-enabled v4 pool.
2. The hook records remaining quota and pass expiry per pool id and trader wallet.
3. `beforeSwap` returns a discounted dynamic fee only for active pass holders.
4. `afterSwap` consumes quota based on actual exact-input swap volume.
5. A custom router can pass trader identity through `hookData` and perform the
   PoolManager unlock, swap, settle, and take flow.
6. The hook rejects static-fee pools because the discount relies on v4 dynamic LP
   fee overrides.

## Current MVP Parameters

| Parameter | Value |
|---|---|
| Base fee | `100` pips = 1 bp |
| Discount fee | `50` pips = 0.5 bp |
| Pass price | `300` payment-token units |
| Quota | `10,000,000` payment-token units |
| Duration | `7 days` |
| Revenue split | `70% LP reserve / 30% treasury reserve` |

These values are demo parameters. The final production values should be
calibrated from real pool volume, per-wallet repeat-flow behavior, route
competition, and LP revenue impact.

## Known Limitations

- Testnet demo uses mock tokens rather than live USDC/USDT0.
- The MVP supports one pass tier.
- Pass identity is bound to one wallet.
- Discounted usage is exact-input only.
- The MVP requires a trusted custom router for pass-aware swaps.
- Standard router or frontend quoting may not reflect pass discounts without a
  custom quoter path.
- LP reserve is tracked in the hook and withdrawable; production must decide
  whether and how that reserve is donated to or otherwise distributed to LPs.
- The contract has not been audited.
- The demo script uses `amountOutMinimum = 0` for the scripted testnet swap. A
  production router must quote and enforce slippage protection.
- The quota currently treats raw input amount as volume. Stablecoin pairs can use
  this as a close demo proxy, but non-stable pairs need USD normalization.

## Production Path

1. Calibrate pass price, quota, discount fee, and LP share from real swap data.
2. Decide the production LP revenue distribution mechanism.
3. Build a pass-aware quoter/router integration.
4. Add a transaction-signing frontend for buy pass, pass status, quote, and swap.
5. Expand tests to include fuzzing, invariant tests, and adversarial hookData cases.
6. Run external audit before handling real funds.
