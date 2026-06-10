# FlowPass Demo Script

## Links

| Item | URL |
|---|---|
| Live demo | https://flowpass.joezhouzmz.workers.dev/ |
| GitHub repo | https://github.com/Joezhouzmz/FlowPass |
| Final swap tx | https://unichain-sepolia.blockscout.com/tx/0xdf2970c1b82d94ebb29b0fb9793d4d6bfae0fba8f8f497a0ec251256a9b6f09d |

## One-Minute Pitch

FlowPass is a Uniswap v4 fee-smoothing yield hook that works like a prepaid
trading membership pass. A trader pays an upfront pass fee, receives lower swap
fees for a fixed amount of future exact-input volume, and returns to the base fee
after the quota is used or the pass expires.

The theme fit is Fee-Smoothing Hooks and Yield Systems. FlowPass improves the LP yield side by
turning recurring order-flow demand into upfront LP reserve, treasury revenue,
and retained swap volume.

## Demo Flow

1. Open the live dashboard.

   ```text
   https://flowpass.joezhouzmz.workers.dev/
   ```

2. Show the top metrics:

   - Hook deployed on Unichain Sepolia.
   - 31 local tests passing.
   - Fee path: 1 bp base fee to 0.5 bp discounted fee.
   - Current demo pass tier: `$300 / $10M`.

3. Walk through the lifecycle:

   - Buy pass.
   - Swap through trusted router.
   - Hook applies discounted dynamic LP fee.
   - Hook consumes quota after the swap.

4. Use the parameter sandbox:

   - Show trader break-even volume.
   - Increase or decrease extra retained flow.
   - Explain that LPs benefit when retained flow offsets the discount.
   - Explain that treasury revenue is upfront pass revenue in this MVP.
   - Point out the LP break-even retained-flow threshold.

5. Show testnet proof:

   - Hook address.
   - Router address.
   - Buy pass transaction.
   - Swap transaction.
   - Remaining quota check.

6. If running locally, verify:

   ```bash
   forge test
   npm run verify:testnet
   ```

## Known MVP Limits

- Testnet demo uses mock tokens rather than live USDC/USDT0.
- Frontend is read-only and does not sign transactions.
- Router is a demo exact-input router.
- Standard Uniswap routing does not automatically understand the pass discount.
- LP reserve is tracked by the hook; production must decide the real LP
  distribution or donation mechanism.
- Contracts are not audited.

## Closing

FlowPass demonstrates a membership-card style mechanism for Uniswap v4 pools:
prepaid access revenue plus discounted quota can smooth LP fee yield and create a
routing advantage when it retains flow that would otherwise leave the pool.
