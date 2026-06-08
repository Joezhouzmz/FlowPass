# FlowPass Testnet Deployment

This file documents the Unichain Sepolia deployment path. It intentionally does
not store RPC URLs, private keys, or keystore names. Public testnet addresses are
included so the demo can be verified.

## Public Unichain Sepolia Addresses

From the official Uniswap v4 deployments page:

| Contract | Address |
|---|---|
| PoolManager | `0x00B036B58a818B1BC34d502D3fE730Db729e62AC` |
| PoolModifyLiquidityTest | `0x5fA728c0a5CfD51bEe4b060773F50554c0C8A7ab` |

FlowPass uses `BEFORE_SWAP_FLAG | AFTER_SWAP_FLAG`, so the hook script mines a
CREATE2 salt before deploying.

## Option A: Mock-Token End-to-End Demo

Use this for a Hookathon demo if you do not yet have testnet USDC/USDT0 ready.
It deploys mock ERC20 tokens, deploys the hook and router, initializes a dynamic
fee v4 pool, adds liquidity through Uniswap's test liquidity router, buys a pass,
swaps through `FlowPassRouter`, and logs the remaining quota.

Do not paste real secrets into chat. Run this locally and replace the placeholders:

```bash
forge script script/DeployUnichainSepoliaMockDemo.s.sol:DeployUnichainSepoliaMockDemo \
  --sig "run(address)" <TREASURY_ADDRESS> \
  --rpc-url <UNICHAIN_SEPOLIA_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

Expected output includes:

- mock token addresses
- FlowPass hook address
- FlowPass router address
- pool id
- remaining pass quota after the demo swap
- pass expiration timestamp

## Option B: Hook + Router Only

Use this when you already have a payment token address, for example testnet USDC.
The default parameters assume a 6-decimal payment token:

| Parameter | Value |
|---|---|
| Pass price | `300e6` |
| Quota | `10_000_000e6` |
| Duration | `7 days` |
| Base fee | `100` pips = 1 bp |
| Discount fee | `50` pips = 0.5 bp |
| LP share | `7000` bps = 70% |

```bash
forge script script/DeployUnichainSepoliaHook.s.sol:DeployUnichainSepoliaHook \
  --sig "deploy(address,address)" <PAYMENT_TOKEN> <TREASURY_ADDRESS> \
  --rpc-url <UNICHAIN_SEPOLIA_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

For non-6-decimal tokens, call `deployWithParams` and pass raw token-unit values:

```bash
forge script script/DeployUnichainSepoliaHook.s.sol:DeployUnichainSepoliaHook \
  --sig "deployWithParams(address,address,uint256,uint128,uint64,uint24,uint24,uint16)" \
  <PAYMENT_TOKEN> <TREASURY_ADDRESS> <PASS_PRICE> <QUOTA> <DURATION_SECONDS> <BASE_FEE> <DISCOUNT_FEE> <LP_SHARE_BPS> \
  --rpc-url <UNICHAIN_SEPOLIA_RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --broadcast
```

## Current Blocker For Actual Broadcast

Resolved for the mock-token demo. The deployment was broadcast successfully to
Unichain Sepolia on 2026-06-08 using a disposable testnet-only wallet.

The remaining production-oriented deployment choices are still open:

- real USDC/USDT0 payment token addresses and decimals
- final treasury address
- final pass price, quota, duration, base fee, discount fee, and LP share
- frontend or router integration path for pass-aware quoting and swaps

## Broadcasted Mock-Token Demo

Network: Unichain Sepolia, chain id `1301`.

Deployment wallet:

```text
0x775717A1460Cce9Ee3c729a0625f09966F72B628
```

Deployed contracts:

| Item | Address |
|---|---|
| Mock token A | `0xd119Da24acdc69190C0a12c1CCD64115c38DE6ac` |
| Mock token B | `0xf06219433b255A42667EFD5F0177194Fa6Dbe0f9` |
| FlowPassV4Hook | `0xEfEf9F8aC2B1fEC9b173Ae3530Cdeb1407BC80C0` |
| FlowPassRouter | `0xD22505dD65B985FBf47c2030a6421536fe0C3159` |

Pool id:

```text
0x6770d05ee2d5efb0a94ea7f27c5212b580b17c1d045c52b3505797721d9c9acb
```

Demo pass state after the broadcasted swap:

| Field | Value |
|---|---|
| Remaining quota | `9999999993981964829423305` |
| Pass expires at | `1781497997` |

Deployment transactions:

| Action | Transaction hash |
|---|---|
| Deploy mock token A | `0xc225ac5773183bee100afc6f8045abf5cf949dfdd3c950d121637a6a4bdaa2f8` |
| Deploy mock token B | `0x9f7f3b60e9e47fb4841e5e425b0679bb715052638f503f42822030c3d8cfee9a` |
| Mint mock token A | `0x0937b6f82480fbf73af4fd6af8764ea2e4e7356173c1187a1ef80a897b6e9d64` |
| Mint mock token B | `0xfd7daae4fe8df69ae46fd72cc2376329e502cb52b69c159266a389de7f7ae19c` |
| Deploy FlowPassV4Hook | `0xfbf8bd1ae03bf2fc93bf8bf2716ae02860bf679f96b4d437891ddd7ca5725b2a` |
| Deploy FlowPassRouter | `0xc3f9f19df1eb1abddda668081913e95e09e6d95f9e374d80680d61925e7c4cc9` |
| Set trusted router | `0x0353956cd52d7dddd7082784e91d9f80623d7f7ed60e8e1af396eeea77107290` |
| Initialize pool | `0x25e3982751e62a462a05f06895fde6b7c4549d9a03de9a6bccc549300dd3aaf3` |
| Add liquidity | `0x06a6941ad46cef0fc78ddb147b85d39cd5557030e6a289ef7e2196a1e6360fad` |
| Buy pass | `0x0a53275caa4add7cab4dfc1dc17750460fe70859a832e83159d6369fe3d0f38b` |
| Swap through FlowPassRouter | `0xdf2970c1b82d94ebb29b0fb9793d4d6bfae0fba8f8f497a0ec251256a9b6f09d` |

Post-deployment checks:

- `FlowPassV4Hook` has on-chain bytecode.
- `FlowPassRouter` has on-chain bytecode.
- `passes(poolId, deploymentWallet)` returns the expected remaining quota and expiry.
- Deployment wallet balance after broadcast: `0.049990696320729184` ETH.

Run the read-only verification script:

```bash
npm run verify:testnet
```

## Faucet Options

Disposable deployment wallet:

```text
0x775717A1460Cce9Ee3c729a0625f09966F72B628
```

Current checked balance after broadcast: `0.049990696320729184` Unichain Sepolia ETH.

Useful faucet options:

| Faucet | URL | Notes |
|---|---|---|
| ETHGlobal | `https://ethglobal.com/faucet/unichain-sepolia-1301` | Lists Unichain Sepolia, chain id `1301`, `0.05 ETH/day`; requires ETHGlobal login. |
| thirdweb | `https://thirdweb.com/unichain-sepolia-testnet` | Lists Unichain Sepolia faucet, `0.01 ETH/day`; may require connecting a wallet. |
| ETH Faucet | `https://ethfaucet.com/networks/unichain/unichain-sepolia` | Lists up to `0.1 ETH every 24 hours`; uses BringID verification. |

Suggested target:

```text
0.001 ETH minimum
0.005 ETH comfortable
0.05 ETH more than enough for repeated demo attempts
```

Check balance:

```bash
cast balance 0x775717A1460Cce9Ee3c729a0625f09966F72B628 --rpc-url https://sepolia.unichain.org
```
