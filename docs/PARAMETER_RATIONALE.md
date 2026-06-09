# FlowPass Parameter Rationale

This document explains the current demo defaults and the data needed to turn
them into production-calibrated parameters.

## Recommended Demo Defaults

| Parameter | Default | Reason |
|---|---:|---|
| Base fee | `100` pips = 1 bp | The target pool is currently treated as a 1 bp stablecoin pool. |
| Discount fee | `50` pips = 0.5 bp | Cuts marginal swap fee in half while preserving LP fee income. |
| Quota | `$10,000,000` | Large enough to represent a market-maker style weekly pass. |
| Pass price | `$300` | Captures 60% of the full-quota fee savings and leaves trader upside. |
| Duration | `7 days` | Short enough to reduce unused-quota risk; long enough to show recurring flow. |
| LP share | `70%` | Gives most upfront revenue to LPs while leaving treasury upside. |
| Treasury share | `30%` | Keeps a visible protocol revenue stream. |
| Extra retained flow assumption | `$6,000,000` | Approximately the flow needed to make LPs whole under the demo defaults. |

These are demo defaults, not audited production settings.

## Math Check

Uniswap fee pips use `1,000,000` as the denominator.

```text
100 pips = 100 / 1,000,000 = 0.01% = 1 bp
50 pips  =  50 / 1,000,000 = 0.005% = 0.5 bp
```

At `$10M` quota:

```text
base_fee_cost = 10,000,000 * 100 / 1,000,000 = $1,000
discount_fee_cost = 10,000,000 * 50 / 1,000,000 = $500
gross_trader_savings = $1,000 - $500 = $500
net_trader_savings = $500 - $300 = $200
trader_break_even_volume = 300 / 0.00005 = $6,000,000
```

The trader is profitable only after using `$6M` of the `$10M` quota. That means
the pass is useful for recurring flow, not one-off flow.

LP math:

```text
lp_upfront_reserve = 300 * 70% = $210
lp_revenue_with_pass_before_extra_flow = discount_fee_cost + lp_upfront_reserve
                                      = 500 + 210 = $710
lp_delta_vs_same_pool_base = 710 - 1,000 = -$290
```

So if the trader would have used this exact pool anyway, the pass costs LPs
`$290` on the first `$10M` of quota.

Extra retained-flow threshold:

```text
extra_flow_needed_for_lp_make_whole = 290 / 0.00005 = $5,800,000
```

The dashboard default rounds this to `$6M`. At that point:

```text
extra_flow_lp_fees = 6,000,000 * 50 / 1,000,000 = $300
lp_total = 500 + 210 + 300 = $1,010
treasury_revenue = $90
```

This makes the mechanism easy to explain:

- Without retained flow, LPs are worse off than the same-pool base-fee benchmark.
- If FlowPass retains roughly `$6M` of flow that would otherwise leave, LPs are
  made whole and treasury still earns `$90`.

## Why These Defaults Are Defensible For Demo

The defaults satisfy three constraints:

| Constraint | Result |
|---|---|
| Trader gets positive upside at full quota | `$200` net savings |
| Trader does not need full quota to break even | Break-even at 60% of quota |
| LPs can be made whole with a clear retained-flow assumption | About `$5.8M` extra flow |

They are not claimed to be mathematically optimal for production because
production optimization requires wallet-level and route-level data.

## Data Needed For Production Calibration

To choose production parameters, collect:

| Data | Use |
|---|---|
| Per-wallet 7-day and 30-day volume | Choose quota and target users. |
| Per-wallet repeat frequency | Estimate pass utilization probability. |
| Competing route fees and execution quality | Estimate how much discount changes routing. |
| Current pool liquidity and price impact | Avoid discounting flow that is not profitable to serve. |
| Share of flow likely to leave without FlowPass | Estimate retained-flow upside. |
| Stablecoin depeg windows | Avoid calibrating only on calm market conditions. |

## Production Optimization Objective

A practical objective is:

```text
maximize expected_protocol_value
```

where:

```text
expected_protocol_value =
  expected_used_quota * discount_fee
  + pass_price
  + expected_extra_retained_flow * discount_fee
  - same_pool_fee_revenue_given_up
```

Subject to:

```text
trader_expected_savings > 0
lp_expected_revenue >= lp_make_whole_target
pass_break_even_volume <= target_wallet_expected_volume
discount_fee < base_fee
```

The key unknown is `expected_extra_retained_flow`. That is why historical route
and wallet data matter more than fee math alone.

## Public Data Caveat

Public exchange pages can show whether Uniswap v4 on Unichain has meaningful
overall activity, but they do not prove the exact FlowPass parameters. The
missing piece is wallet-level recurring USDC/USDT0 flow and counterfactual route
choice: whether the trader would have used this pool without the pass.

