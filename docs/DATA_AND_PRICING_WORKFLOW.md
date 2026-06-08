# FlowPass Data And Pricing Workflow

This workflow turns FlowPass pass parameters into data-backed choices instead of
fixed guesses.

## Current Demo Economics

Current placeholder values:

| Parameter | Value |
|---|---|
| Base fee | `100` pips = 1 bp |
| Discount fee | `50` pips = 0.5 bp |
| Discount size | 0.5 bp |
| Quota | `$10,000,000` |
| Pass price | `$300` |
| LP share | 70% |
| Treasury share | 30% |

At full quota:

| Metric | Formula | Value |
|---|---|---|
| Base-fee cost | `$10,000,000 * 100 / 1,000,000` | `$1,000` |
| Discount-fee cost | `$10,000,000 * 50 / 1,000,000` | `$500` |
| Gross trader fee savings | `$1,000 - $500` | `$500` |
| Net trader savings | `$500 - $300 pass price` | `$200` |
| Trader break-even volume | `$300 / 0.00005` | `$6,000,000` |
| LP upfront reserve | `$300 * 70%` | `$210` |
| Treasury reserve | `$300 * 30%` | `$90` |
| LP revenue vs same-pool base flow | `$500 + $210 - $1,000` | `-$290` |

Interpretation:

- The trader benefits only if they use more than about `$6M` of quota.
- LPs are not fully made whole if this was already captive same-pool flow.
- LPs still benefit if FlowPass retains or attracts volume that would otherwise
  route to another pool.
- The core production question is how much incremental or retained order flow the
  pass creates.

## Data Needed

Collect at least seven to thirty days of data for the target pair and competing
routes:

| Input | Why it matters |
|---|---|
| Per-wallet swap volume distribution | Finds traders likely to use a pass fully. |
| Repeat trading frequency per wallet | Separates recurring flow from one-off trades. |
| Route alternatives and fee tiers | Estimates how sensitive flow is to fee changes. |
| Effective execution cost by route | Separates fee savings from price impact. |
| LP liquidity and utilization | Shows whether lower fees need stronger LP compensation. |
| Stablecoin depeg or volatility windows | Prevents pricing from being tuned only to calm markets. |
| Wallet clustering assumptions | Flags market makers using multiple wallets. |

## Decision Steps

1. Define candidate pass users.

   Start with wallets whose seven-day volume is above the pass break-even volume.
   For the demo settings, that is roughly `$6M` per week.

2. Estimate usage probability.

   For each candidate wallet, estimate the probability that it will consume the
   full quota before expiry. A pass that is only half used changes the trader
   value and LP economics materially.

3. Estimate retained flow.

   Compare the FlowPass pool against competing routes. If a trader would have
   used the pool anyway, the pass reduces LP fee revenue. If the trader would
   have left, the pass creates new LP revenue.

4. Choose discount fee.

   The discount should be just large enough to change routing behavior for the
   target traders. For stable/stable pools, test small differences first because
   the market is highly competitive.

5. Choose pass price.

   A practical starting formula:

   ```text
   pass_price = expected_quota_used * (base_fee - discount_fee) / 1,000,000 * trader_capture_rate
   ```

   `trader_capture_rate` should be below 1 so the trader still has a reason to
   buy the pass. The demo uses `$300 / $500 = 60%`.

6. Choose LP share.

   A practical starting formula:

   ```text
   lp_share = min(100%, target_lp_compensation / pass_price)
   ```

   where:

   ```text
   target_lp_compensation = same_pool_baseline_fee_loss * make_whole_target
   ```

   For a membership strategy, the make-whole target can be below 100% if the
   pass meaningfully retains flow that would otherwise leave.

7. Choose quota and duration.

   A smaller quota lowers unused-pass risk for the trader. A larger quota creates
   stronger commitment to the FlowPass pool. For stablecoin market makers, seven
   days is a reasonable demo interval; production should test daily, weekly, and
   monthly passes.

8. Validate with counterfactual revenue.

   Compare:

   ```text
   no_pass_revenue = captive_volume * base_fee
   flowpass_revenue = used_quota * discount_fee + upfront_lp_share + treasury_share
   lost_flow_revenue = 0
   ```

   The key metric is not just fee per swap. It is whether FlowPass increases
   total retained volume and total pool revenue after discounts.

## Stablecoin Versus Non-Stablecoin Pairs

For stable/stable pairs:

- Quota can be denominated in input token units if both assets track USD closely.
- Parameter changes should be conservative because routing competition is tight.
- Small fee differences can move significant volume.

For volatile pairs:

- Quota should be normalized to USD value.
- The hook or router needs a pricing source.
- Production needs oracle and manipulation-risk handling.
- Pass price should account for price volatility and expected unused quota.

## MVP Recommendation

Keep the submitted demo at one tier:

| Parameter | MVP value |
|---|---|
| Quota | `$10M` |
| Pass price | `$300` |
| Duration | 7 days |
| Base fee | 1 bp |
| Discount fee | 0.5 bp |
| LP share | 70% |

Use the dashboard parameter sandbox to explain that these are not final production
parameters. The next production milestone is to replace the assumptions with
wallet-level swap data and route-competition analysis.

