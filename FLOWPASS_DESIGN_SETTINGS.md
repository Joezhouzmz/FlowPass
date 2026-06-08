# FlowPass Design Settings

FlowPass is a Uniswap v4 fee hook that works like a prepaid trading membership pass.
A trader pays an upfront pass fee, receives discounted swap fees for a fixed amount
of future trading volume, and is economically encouraged to route future flow through
the FlowPass-enabled pool.

This document records the current product, protocol, and implementation decisions
for the MVP, plus the execution workflows for items that are still tentative.

## 1. Current Setting Table

| Module | Item | Current Setting | Status | Notes |
|---|---|---|---|---|
| Product positioning | Product type | Prepaid trading membership pass | Decided | This is not a stored-value card. The pass fee buys eligibility for discounted future volume. |
| Product goal | Main objective | Bind future order flow | Decided | The pass creates switching cost and marginal fee advantage in a competitive routing environment. |
| Target users | User type | High-frequency traders, market makers, recurring flow traders | Decided | Low-frequency users may not benefit enough because the base fee is already low. |
| Chain | Network | Unichain | Decided | MVP targets Unichain only. |
| Pool | Pair | USDC / USDT0 | Decided | Stablecoin pair is the cleanest first use case. |
| Pool fee | Base fee | `100 = 0.01% = 1 bp` | Tentative | Non-pass traders pay this base fee. |
| Hook type | Uniswap v4 hook type | Dynamic fee hook | Decided | The hook returns a lower swap fee for active pass holders. |
| Pool creation | Existing pool support | Must create a new FlowPass-enabled v4 pool | Decided | A hook must be included in the pool key at initialization. Existing pools cannot be retrofitted. |
| Pass model | Core model | Upfront membership fee plus discounted quota | Decided | The user pays once and receives discounted fee eligibility for a limited quota and duration. |
| Pass fee | Payment token | USDC first | Tentative | Later versions may support USDT0 or mixed payment. |
| Pass fee | Mixed payment by pool state | Not in MVP | Decided | Possible later, but adds price conversion and manipulation risk. |
| Pass pricing | Pricing mode | Fixed pass tiers first | Decided | Fully dynamic pass pricing is deferred. |
| Pass pricing | Price updater | Owner or manager updates tiers | Tentative | Production version should use timelock, governance, or signed quotes. |
| Pass tiers | Number of tiers | 1 to 3 fixed tiers | Tentative | Candidate tiers: weekly small, weekly pro, monthly pro. |
| Pass value formula | Trader net benefit | `(baseFee - discountFee) * expectedVolume - passPrice` | Decided | A trader buys only if expected savings exceed pass price. |
| Discount fee | Discount fee | `0.5 bp` candidate | Tentative | From 1 bp to 0.5 bp saves about 500 USDC on 10M USD volume. |
| Pass duration | Duration | 7 days candidate | Tentative | Weekly membership is easiest to reason about. |
| Quota unit | Measurement unit | USD notional volume | Decided | For USDC/USDT0, input amount is approximately USD volume. |
| Non-stable expansion | Quota unit | Still USD notional volume | Decided | Token amount is not comparable across volatile assets. |
| Non-stable expansion | Price source | TWAP, oracle, or current pool price | Later | Production should avoid relying only on current spot pool price. |
| Identity | Pass binding | Single wallet address | Decided | MVP binds one pass to one wallet. |
| Multi-address users | Market maker groups | Not in MVP | Decided | Later versions can add group IDs or allowlists. |
| Transferability | Pass transfer | Non-transferable | Tentative | Simpler and closer to an address-bound membership card. |
| Swap mode | Exact-input swaps | Eligible for pass discount | Decided | Exact-input makes quota checking tractable before swap execution. |
| Swap mode | Exact-output swaps | No pass discount in MVP | Decided | Exact-output input volume is not known precisely before execution. |
| Router | Trusted router | Use trusted router for pass-enabled swaps | Tentative | Prevents users from spoofing another trader in hook data. |
| Trader identity | Trader source | Trusted router passes trader in hookData | Tentative | The hook should not blindly trust router-like senders from arbitrary callers. |
| Quota accounting | Deduction time | Deduct in `afterSwap` based on actual executed volume | Decided | Handles price limits and partial fills correctly. |
| Partial quota | Insufficient remaining quota | Full coverage required for discount in MVP | Decided | If remaining quota is less than requested input, use base fee. |
| Partial quota | Mixed fee inside one swap | Not in MVP | Decided | Requires router-level split or more complex custom accounting. |
| Expiration | Expired pass | Reverts to base fee | Decided | Unused quota expires with no refund. |
| Exhaustion | `quota = 0` | Reverts to base fee | Decided | No extra action needed. |
| Refund | Refunds | No refunds in MVP | Decided | Fits membership-card economics and avoids complex settlement. |
| Renewal | Renewal | Allowed | Decided | Trader can extend membership. |
| Top-up | Quota top-up | Allowed | Decided | Trader can add more discounted quota. |
| Revenue allocation | Upfront revenue | Split between LPs and treasury | Decided | LPs need compensation for lower future swap fees. |
| Revenue split | Initial split | `70% LP / 30% treasury` | Tentative | Starting point; should be calibrated by simulation. |
| LP revenue | LP allocation method | Donate LP share to pool | Tentative | Gives current LPs part of pass revenue. |
| Treasury revenue | Treasury allocation method | Keep treasury share in hook, withdrawable by treasury | Decided | The hook contract can hold USDC and later transfer it to treasury. |
| Treasury address | Treasury storage | `address public treasury` | Decided | Set at deployment; may be updatable by owner. |
| Access control | Parameter updater | Owner or manager | Tentative | MVP can be owner-managed; production should harden governance. |
| Data requirement | Historical swap data | Needed from Dune, subgraph, or RPC | Decided | Required to calibrate price, quota, duration, and revenue split. |
| Data fields | Minimum fields | trader, timestamp, amount0, amount1, poolId, tx hash | Decided | Used to compute trader volume, frequency, retention, and pass value. |
| Parameter backtest | Objective | Find parameters where traders benefit and LP plus treasury revenue does not degrade | Decided | Must evaluate total order flow, not just per-swap fee. |
| MVP contract | Main hook file | `src/FlowPassHook.sol` | Decided | Implements pass purchase, dynamic fee, quota deduction, and revenue allocation. |
| Tests | Foundry tests | `test/FlowPassHook.t.sol` | Decided | Covers purchase, discount, expiry, quota exhaustion, and partial quota. |
| Deployment | Hook deployment script | `script/DeployFlowPassHook.s.sol` | Decided | v4 hook address must encode hook permission flags. |
| Pool setup | Pool initialization script | `script/InitializePool.s.sol` | Decided | Creates the FlowPass-enabled USDC/USDT0 pool. |
| Test command | Unit test command | `forge test` | Decided | Foundry is the default testing framework. |
| Test scope | MVP testing | Unit tests plus local pool simulation | Decided | Fork tests can be added after contract logic is stable. |

## 2. Current MVP Parameter Draft

| Parameter | Draft Value |
|---|---|
| Pool | USDC / USDT0 on Unichain |
| Base fee | `1 bp` |
| Discount fee | `0.5 bp` |
| Pass duration | `7 days` |
| Quota unit | USD notional volume |
| Payment token | USDC |
| Revenue split | `70% LP / 30% treasury` |
| Identity | Single wallet |
| Swap mode | Exact-input only |
| Partial quota rule | Remaining quota must fully cover requested input, otherwise base fee |
| Refund | No |
| Renewal | Yes |
| Top-up | Yes |
| Pass pricing | Fixed tiers first |
| Price updater | Owner or manager for MVP |

## 3. Workflows To Decide Tentative Items

The following items are intentionally not final. They should be decided through
data analysis, simulation, and implementation constraints.

### 3.1 Decide Base Fee Confirmation

Current tentative setting: `100 = 1 bp`.

Goal: confirm whether the FlowPass pool should use the same fee level as the
target competitive pool or a modified base fee.

Execution steps:

1. Identify the exact USDC and USDT0 token addresses on Unichain.
2. Identify the current USDC/USDT0 v4 pool with fee `100`, if it exists.
3. Confirm how much liquidity and volume that pool has.
4. Compare it against competing stablecoin routes on Unichain.
5. Decide whether matching `1 bp` is necessary for competitive routing.
6. If the market already expects `1 bp`, keep base fee at `1 bp`.
7. If liquidity is weak and FlowPass must compensate LPs more aggressively, test whether `2 bp` base fee plus pass discount still routes competitively.

Decision rule:

```text
Use the lowest base fee that remains attractive to routers and still gives LPs enough expected revenue.
For MVP, default to 1 bp unless data shows that LP economics are impossible.
```

Outputs:

- Confirmed base fee.
- List of competing routes and their fee levels.
- Reason for keeping or changing `1 bp`.

### 3.2 Decide Payment Token

Current tentative setting: USDC only.

Goal: decide whether users can buy passes with USDC only, USDT0 only, or either token.

Execution steps:

1. Check which token is more commonly used as accounting currency on Unichain.
2. Check token transfer behavior and decimals for USDC and USDT0.
3. Estimate implementation complexity:
   - USDC only: simplest.
   - USDT0 only: similarly simple.
   - Either token: more user-friendly, more branches and tests.
   - Mixed USDC plus USDT0 payment: most complex and not needed for MVP.
4. Decide whether pass price should be denominated in USDC even if payment supports USDT0.
5. If allowing USDT0 payment, define whether `1 USDT0 = 1 USDC` for MVP.

Decision rule:

```text
Use USDC only for MVP unless target traders strongly prefer USDT0 payment.
Add USDT0 payment after the base hook is tested.
Do not support mixed payment in MVP.
```

Outputs:

- Payment token list.
- Price denomination token.
- Conversion rule if more than one token is supported.

### 3.3 Decide Pass Tiers, Price, Quota, and Duration

Current tentative setting: 1 to 3 fixed tiers, 7-day duration, 0.5 bp discount.

Goal: set pass tiers so that traders have positive expected savings while LPs and treasury receive sufficient upfront revenue.

Core formulas:

```text
grossTraderSavings = (baseFee - discountFee) * expectedDiscountedVolume
traderNetSavings = grossTraderSavings - passPrice
lpFeeLoss = (baseFee - discountFee) * actualDiscountedVolume
lpUpfrontCompensation = passPrice * lpShare
treasuryRevenue = passPrice * treasuryShare
```

Execution steps:

1. Pull at least 30 days of historical USDC/USDT0 swap data.
2. Group swaps by trader address.
3. For each trader, compute:
   - daily volume
   - weekly volume
   - number of active days
   - number of swaps
   - median trade size
   - max trade size
   - retention from week to week
4. Filter for likely pass buyers:
   - recurring weekly activity
   - enough volume for fee savings to exceed pass price
   - not just one-off large trades
5. Generate candidate tiers, for example:

| Candidate | Duration | Quota | Discount Fee | Pass Price Logic |
|---|---:|---:|---:|---|
| Weekly Small | 7 days | 1M USD | 0.5 bp | 40% to 70% of expected max savings |
| Weekly Pro | 7 days | 10M USD | 0.5 bp | 40% to 70% of expected max savings |
| Monthly Pro | 30 days | 40M USD | 0.5 bp | 40% to 70% of expected max savings |

6. Backtest each trader under each candidate tier:
   - Would the trader rationally buy?
   - How much would the trader save?
   - How much fee would LPs lose?
   - How much upfront revenue is generated?
   - Does the pass shift enough volume to this pool to justify the discount?
7. Pick tiers that produce:
   - positive trader net savings for target users
   - no severe LP revenue degradation
   - simple enough messaging
8. Validate on a later time window:
   - Use one period to fit parameters.
   - Use a later period to test if they still work.

Decision rule:

```text
Set passPrice below expected gross savings, but high enough that LP upfront compensation covers a meaningful share of LP fee loss.
Avoid tiers that only benefit one-off whales.
Prefer tiers that match recurring weekly trading behavior.
```

Outputs:

- Final tier table.
- Expected buyer count.
- Expected trader savings.
- Expected LP revenue impact.
- Expected treasury revenue.

### 3.4 Decide Discount Fee

Current tentative setting: `0.5 bp`.

Goal: choose a discount fee low enough to influence routing but not so low that LP economics break.

Execution steps:

1. Test candidate discount fees:
   - `0.75 bp`
   - `0.5 bp`
   - `0.25 bp`
   - `0 bp` only as a stress case
2. For each candidate, compute trader savings at common quota levels:
   - 1M USD
   - 5M USD
   - 10M USD
   - 50M USD
3. Estimate LP fee loss per tier.
4. Estimate whether pass upfront revenue can compensate enough of that loss.
5. Compare against competing pools and aggregators:
   - If the fee discount does not change routing, it may not matter.
   - If the discount is too aggressive, LPs may leave.

Decision rule:

```text
Use the smallest discount that creates a meaningful routing advantage for target traders.
Default to 0.5 bp for MVP because it is easy to explain: half-price fee for eligible volume.
```

Outputs:

- Selected discount fee.
- Trader savings table by volume.
- LP fee loss table by volume.

### 3.5 Decide Revenue Split Between LP and Treasury

Current tentative setting: `70% LP / 30% treasury`.

Goal: split upfront pass revenue so LPs are compensated for lower swap fees while the protocol treasury captures value for building and operating FlowPass.

Execution steps:

1. For each pass tier, compute expected LP fee loss:

```text
lpFeeLoss = (baseFee - discountFee) * expectedDiscountedVolume
```

2. For candidate splits, compute LP compensation:

```text
lpCompensation = passPrice * lpShare
treasuryRevenue = passPrice * treasuryShare
```

3. Test candidate splits:
   - 90% LP / 10% treasury
   - 80% LP / 20% treasury
   - 70% LP / 30% treasury
   - 60% LP / 40% treasury
   - 50% LP / 50% treasury
4. Compare:
   - LP compensation as a percentage of LP fee loss.
   - Treasury revenue per pass.
   - Whether LPs still prefer supporting this pool.
   - Whether project revenue is enough to justify maintaining the hook, router, frontend, and analytics.
5. Decide whether split is global or tier-specific:
   - Global split is simpler.
   - Tier-specific split can compensate LPs more on aggressive discount tiers.

Decision rule:

```text
Use 70/30 as the MVP default.
Move toward 80/20 or 90/10 if LP revenue degradation is too high.
Move toward 60/40 or 50/50 only if LP compensation remains healthy and treasury capture is the priority.
```

Outputs:

- Final LP share.
- Final treasury share.
- Whether split is global or tier-specific.
- LP compensation ratio for each pass tier.

### 3.6 Decide LP Allocation Method

Current tentative setting: donate LP share to the pool.

Goal: decide how the LP portion of pass revenue reaches liquidity providers.

Candidate approaches:

| Approach | Description | Pros | Cons |
|---|---|---|---|
| Donate to pool | Hook sends LP share into the pool through v4 donation mechanics | Directly benefits current LPs | Timing and distribution depend on current liquidity |
| Accumulate and periodic donate | Hook stores LP share and donates periodically | Lower operational frequency | Requires keeper or admin process |
| Separate rewards contract | LPs claim rewards from an external contract | Flexible accounting | More contracts, more complexity |
| All to treasury, offchain LP incentives | Treasury handles incentives separately | Operationally flexible | Less transparent and weaker LP trust |

Execution steps:

1. Confirm v4 donation mechanics for the target pool.
2. Check whether donation creates any edge cases around zero liquidity or current active range.
3. Decide whether donation should happen immediately on pass purchase or periodically.
4. Add tests for:
   - pass purchase with active liquidity
   - pass purchase with no active liquidity
   - repeated pass purchases
   - treasury withdraw after LP share separation
5. Compare gas cost of immediate donation vs periodic donation.

Decision rule:

```text
Use immediate donation for MVP if it is simple and reliable in tests.
Use accumulated periodic donation if immediate donation creates gas or accounting issues.
```

Outputs:

- LP allocation mechanism.
- Donation timing.
- Edge case handling.

### 3.7 Decide Trusted Router Requirement

Current tentative setting: pass-enabled swaps use a trusted router.

Goal: prevent spoofing of trader identity while keeping the MVP simple.

Problem:

```text
If the hook trusts arbitrary hookData, a user can pass someone else's trader address and consume or misuse their pass.
```

Candidate approaches:

| Approach | Description | Pros | Cons |
|---|---|---|---|
| Direct wallet only | The hook treats swap caller as trader | Simple | Breaks when caller is a router |
| Trusted router | Only approved router can pass trader in hookData | Practical for MVP | Requires maintaining trusted router list |
| Signature-based identity | Trader signs swap intent and hook verifies signature | Stronger security | More complex and more gas |
| Permit/session key | Trader authorizes a router/session key | Good UX later | More complex account model |

Execution steps:

1. Decide whether MVP swaps are routed through a custom FlowPass router.
2. If yes, store `mapping(address => bool) trustedRouters`.
3. In hook logic:
   - if caller is trusted router, decode trader from hookData
   - otherwise, do not apply pass discount
4. Add tests:
   - trusted router can apply pass
   - untrusted caller cannot spoof pass holder
   - wrong trader in hookData is rejected or ignored
   - pass holder cannot be charged quota by arbitrary caller
5. Later, evaluate signature-based usage for broader integrations.

Decision rule:

```text
Use trusted router for MVP.
Do not let arbitrary hookData determine pass ownership.
```

Outputs:

- Router trust model.
- Router update permissions.
- Spoofing tests.

### 3.8 Decide Transferability

Current tentative setting: non-transferable pass.

Goal: decide whether a pass can move between wallets.

Execution steps:

1. Decide whether FlowPass is closer to:
   - personal membership
   - transferable prepaid asset
2. Evaluate abuse risk:
   - pass reselling
   - secondary markets
   - stolen or compromised account usage
   - quota sharing outside intended user group
3. Evaluate user need:
   - market makers may rotate wallets
   - teams may want shared access
4. If transferability is needed later, consider replacing transfer with controlled delegation:
   - allowlisted secondary wallet
   - group account
   - signed delegation

Decision rule:

```text
Keep passes non-transferable in MVP.
Add group or delegation later instead of unrestricted transfer.
```

Outputs:

- Transferability decision.
- Upgrade path if multi-address usage becomes important.

### 3.9 Decide Parameter Update Permissions

Current tentative setting: owner or manager.

Goal: decide who can update pass prices, tiers, fee settings, split ratios, and router addresses.

Candidate permissions:

| Permission Model | Pros | Cons |
|---|---|---|
| Single owner | Fast and simple | Centralization risk |
| Owner plus manager roles | More operational flexibility | More role complexity |
| Multisig | Better security | Slower operations |
| Timelock | Users can react to changes | Slower and heavier |
| Governance | Most decentralized | Too heavy for MVP |

Execution steps:

1. List all mutable parameters:
   - treasury address
   - pass tiers
   - discount fee
   - revenue split
   - trusted router list
   - pause status
2. Classify them:
   - low-risk operational updates
   - high-risk economic updates
3. For MVP:
   - owner can update all parameters
   - events emitted for every update
4. For production:
   - treasury and economic parameters controlled by multisig or timelock
   - operational router updates controlled by manager plus delay or multisig
5. Add tests that unauthorized users cannot update parameters.

Decision rule:

```text
Use owner-managed parameters for MVP.
Design storage and events so the control model can later move to multisig or timelock.
```

Outputs:

- Permission table.
- Events for parameter updates.
- Production hardening plan.

### 3.10 Decide Non-Stablecoin Expansion Pricing

Current decided direction: quota remains USD notional volume.

Goal: define how FlowPass works when the pair is not stable/stable.

Execution steps:

1. Keep pass price denominated in stablecoin.
2. Keep quota denominated in USD notional.
3. For each swap, convert input token amount to USD notional.
4. Evaluate price sources:
   - current pool spot price
   - pool TWAP
   - Chainlink or external oracle
   - offchain signed quote
5. Identify manipulation risks:
   - thin liquidity spot price manipulation
   - same-block price movement
   - oracle lag
6. Choose source based on pool type:
   - stable/stable: input amount is acceptable for MVP
   - deep ETH/USDC: TWAP or oracle
   - long-tail assets: avoid until oracle quality is good

Decision rule:

```text
Do not expand to volatile pairs until USD volume conversion is robust.
For MVP, avoid oracle complexity by staying with USDC/USDT0.
```

Outputs:

- Supported pair categories.
- USD valuation method.
- Oracle or TWAP design.

## 4. Data Workflow For Parameter Calibration

This workflow is used to move from draft settings to evidence-based parameters.

### 4.1 Data Sources

Candidate sources:

| Source | Use | Notes |
|---|---|---|
| Dune | Fast historical analysis | Good for exploratory SQL and dashboards. |
| Uniswap v4 subgraph | Structured pool and swap queries | Good if the target pool is indexed. |
| Unichain RPC logs | Lowest-level source of truth | More work; needed if indexers are incomplete. |
| Existing local analytics code | Backtest-style processing | Can reuse patterns from prior Unichain analysis projects. |

### 4.2 Required Fields

Minimum required fields:

| Field | Reason |
|---|---|
| `poolId` | Identify the exact USDC/USDT0 pool. |
| `timestamp` | Build daily and weekly trader behavior. |
| `txHash` | Deduplicate and audit swaps. |
| `trader` or sender | Group flow by user identity. |
| `amount0` | Compute token0 volume. |
| `amount1` | Compute token1 volume. |
| `sqrtPriceX96` or price | Estimate USD notional if needed. |
| `tick` | Optional; helps understand execution conditions. |

### 4.3 Analysis Steps

1. Identify the target pool.
2. Pull at least 30 days of swaps.
3. Normalize token amounts by decimals.
4. Convert volume to USD notional.
5. Group by trader address.
6. Compute weekly metrics:
   - total volume
   - number of swaps
   - average trade size
   - active days
   - repeat activity
7. Segment traders:
   - one-off users
   - medium recurring users
   - high-frequency users
   - large market makers
8. Simulate candidate pass tiers.
9. Compare outcomes:
   - trader net savings
   - LP fee loss
   - LP upfront compensation
   - treasury revenue
   - volume likely retained by FlowPass
10. Pick initial tier settings.
11. Re-run on a later validation period.

### 4.4 Calibration Outputs

The calibration should produce:

- recommended pass tiers
- expected number of buyers
- expected total discounted volume
- expected LP fee loss
- expected LP compensation from upfront pass fees
- expected treasury revenue
- sensitivity table across discount fee and revenue split

## 5. Implementation File Plan

When we say "build the hook", the MVP project should eventually contain:

```text
FlowPass/
  foundry.toml
  remappings.txt
  src/
    FlowPassHook.sol
    FlowPassTypes.sol
  test/
    FlowPassHook.t.sol
  script/
    DeployFlowPassHook.s.sol
    InitializePool.s.sol
  docs/
    FLOWPASS_DESIGN_SETTINGS.md
```

This document can be moved into `docs/` once the Foundry project is scaffolded.

## 6. MVP Contract Behavior

Expected MVP behavior:

1. User buys pass with USDC.
2. Hook splits upfront revenue:
   - LP share is donated or reserved for LP allocation.
   - Treasury share remains in the hook for treasury withdrawal.
3. Hook records pass state:

```solidity
struct Pass {
    uint128 remainingUsdVolume;
    uint64 expiresAt;
}
```

4. User swaps exact-input through trusted router.
5. Router passes trader identity through hook data.
6. In `beforeSwap`, hook checks:
   - trader has active pass
   - pass is not expired
   - remaining quota fully covers requested input
7. If eligible, hook returns discount fee.
8. In `afterSwap`, hook deducts actual executed volume.
9. Once quota is zero or expired, user returns to base fee.

## 7. Test Plan

### 7.1 Unit Tests

Required Foundry tests:

| Test | Expected Result |
|---|---|
| Buy pass with USDC | Pass state is created and revenue split is recorded. |
| Buy pass with insufficient allowance | Reverts. |
| Active pass exact-input swap | Discount fee applies. |
| No pass swap | Base fee applies. |
| Expired pass swap | Base fee applies. |
| Quota exhausted | Base fee applies after exhaustion. |
| Partial quota insufficient | Base fee applies instead of discount. |
| Partial fill | Deducts actual executed volume, not requested amount. |
| Untrusted router spoofing | Cannot use another wallet's pass. |
| Unauthorized parameter update | Reverts. |
| Treasury withdraw | Only authorized treasury or owner can withdraw. |

### 7.2 Fork Tests

Later fork-test goals:

1. Fork Unichain.
2. Verify token addresses and decimals.
3. Verify PoolManager address.
4. Deploy hook with correct permission flags.
5. Initialize FlowPass-enabled USDC/USDT0 pool.
6. Execute a pass-enabled swap.
7. Verify quota deduction and fee behavior.

## 8. Recommended Next Steps

1. Scaffold Foundry project in `/Users/joezhou/PycharmProject/FlowPass`.
2. Move this document into `docs/FLOWPASS_DESIGN_SETTINGS.md`.
3. Add an initial `src/FlowPassHook.sol` skeleton.
4. Add pass purchase and storage tests.
5. Add exact-input dynamic fee tests.
6. Add quota deduction tests.
7. Pull historical USDC/USDT0 data.
8. Run parameter calibration.
9. Finalize tentative economic parameters.
