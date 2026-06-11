# FlowPass Hook Submission Form Draft

Use this as the source text for the final Hook Submission form.

## Fields We Can Fill Now

| Field | Draft answer |
|---|---|
| Project Title | FlowPass |
| Submission Type | Hook project / Uniswap v4 hook demo |
| GitHub Repo | https://github.com/Joezhouzmz/FlowPass |
| My Github repo is public | Yes |
| Project link | https://flowpass.joezhouzmz.workers.dev/ |
| Did you integrate any partners? | No, unless the form lists Unichain as a required sponsor/partner option. |
| Partner integration explanation | N/A. The project deploys on Unichain Sepolia and uses Uniswap v4 hook mechanics, but it does not rely on a separate sponsor integration. |
| Does your project address the theme? | Yes, my project addresses the theme. |
| Tags | Fee-Smoothing Hook, Yield System, Dynamic Fees, LP Revenue Smoothing, Trading Volume Rewards, Order Flow Retention, Uniswap v4, Unichain |
| Do you plan to continue? | Yes :) |

## Fields You Must Confirm

| Field | Needed from you |
|---|---|
| Project ID | Must match the form format, for example `HK-UHI8-0123`. Use the exact ID Atrium assigned to FlowPass. |
| Email | Use the email registered for the hookathon. |
| x.com handle | Use your exact x.com handle. |
| Cohort | Select the cohort shown for your enrollment. The pasted form mentions UHI9 theme but the Project ID example says UHI8, so do not guess this. |
| Project Thumbnail | Upload `docs/flowpass-thumbnail.png`. The editable source is `docs/flowpass-thumbnail.svg`. |
| Demo video link | Required. Use Loom, YouTube unlisted, or a shareable Google Drive video link. |
| Slide deck link | Optional in the pasted form, but useful if you make a short deck. |
| Did you work with a team? | Choose Yes only if there are other official team members. |
| UHI rating and feedback | Personal answer. A draft is included below. |

## 1-2 Sentence Description

FlowPass is a Uniswap v4 fee-smoothing yield hook that sells prepaid trading
passes: traders pay upfront for discounted future swap volume, and the hook
tracks quota and expiry per wallet. The pass revenue is split into LP reserve and
treasury revenue, while the discount helps retain recurring order flow in
competitive pools.

## Theme Answer

Yes. FlowPass addresses the theme under Fee-Smoothing Hooks and Yield Systems.
It does not directly insure impermanent loss, but it improves LP yield stability
by converting future order-flow demand into upfront LP reserve and by modeling
the retained flow needed to offset discounted fees.

## Problem / Background

In highly competitive pools, especially stablecoin-style routing markets, traders
can choose between many similar venues. Prices, liquidity, fees, and routing are
transparent, and traders can switch pools with very low friction. A simple fee
discount may attract flow, but it can also reduce LP revenue if the same flow
would have stayed anyway.

FlowPass is inspired by Costco-style membership economics: a user pays upfront,
then receives lower prices later. The merchant may earn less per transaction, but
the membership creates commitment, repeat usage, and higher total volume.
FlowPass applies this idea to AMMs by asking recurring traders to prepay for a
time-limited discounted quota, giving them a reason to keep routing through the
FlowPass pool.

## Impact

FlowPass turns swap-fee competition into a structured yield product and business
model. Traders get lower marginal execution costs after buying a pass, LPs get
discounted swap fees plus an upfront reserve allocation, and the protocol captures
prepaid revenue through the hook treasury.

The project also shows why hooks matter commercially, not only technically. In a
transparent AMM market, purely technical advantages can be copied or arbitraged
away. FlowPass creates pool-level differentiation through prepaid access, quota,
expiry, and revenue sharing. It also gives hook creators a path to sustainable
treasury revenue, which can help incentivize more serious mechanism design in the
Uniswap v4 hook ecosystem.

## Challenges

The hardest parts were translating a membership-pass model into real Uniswap v4
hook mechanics, handling dynamic LP fee overrides correctly, and avoiding quota
mis-accounting around swaps. The MVP also needed a custom exact-input router so
the hook could receive trader identity in `hookData`, plus a clear explanation of
why standard router quoting does not automatically understand pass discounts.

## UHI Feedback Draft

The most helpful parts were the focus on real Uniswap v4 hook mechanics, the
deadline structure, and the requirement to make the hook demoable instead of
stopping at an idea. I would have liked even more examples of final submissions
that clearly distinguish production-ready hooks from MVP demos.
