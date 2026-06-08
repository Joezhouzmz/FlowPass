const BASE_FEE = 100;
const DISCOUNT_FEE = 50;
const PASS_PRICE = 300;
const QUOTA = 10_000_000;
const DURATION_SECONDS = 7 * 24 * 60 * 60;
const LP_SHARE_BPS = 7000;
const BPS_DENOMINATOR = 10000;

class FlowPassDemo {
  constructor() {
    this.now = 1_717_000_000;
    this.pass = { remainingUsdVolume: 0, expiresAt: 0 };
    this.lpRevenueReserve = 0;
    this.treasuryRevenueReserve = 0;
  }

  buyPass() {
    const lpShare = (PASS_PRICE * LP_SHARE_BPS) / BPS_DENOMINATOR;
    const treasuryShare = PASS_PRICE - lpShare;

    this.lpRevenueReserve += lpShare;
    this.treasuryRevenueReserve += treasuryShare;
    this.pass.remainingUsdVolume += QUOTA;
    this.pass.expiresAt = Math.max(this.pass.expiresAt, this.now) + DURATION_SECONDS;

    return {
      action: "buyPass",
      passPriceUsdc: PASS_PRICE,
      quotaAddedUsd: QUOTA,
      expiresAt: this.pass.expiresAt,
      lpShareUsdc: lpShare,
      treasuryShareUsdc: treasuryShare
    };
  }

  swapExactInput(requestedUsdVolume, actualUsdVolume) {
    if (actualUsdVolume > requestedUsdVolume) {
      throw new Error("actualUsdVolume cannot exceed requestedUsdVolume for exact-input swaps");
    }

    const discounted =
      requestedUsdVolume > 0 &&
      this.pass.expiresAt >= this.now &&
      this.pass.remainingUsdVolume >= requestedUsdVolume;

    const fee = discounted ? DISCOUNT_FEE : BASE_FEE;
    const consumedUsdVolume = discounted ? actualUsdVolume : 0;
    this.pass.remainingUsdVolume -= consumedUsdVolume;

    return {
      action: "swapExactInput",
      requestedUsdVolume,
      actualUsdVolume,
      fee,
      discounted,
      consumedUsdVolume,
      remainingUsdVolume: this.pass.remainingUsdVolume
    };
  }

  swapExactOutput(requestedUsdVolume, actualUsdVolume) {
    return {
      action: "swapExactOutput",
      requestedUsdVolume,
      actualUsdVolume,
      fee: BASE_FEE,
      discounted: false,
      consumedUsdVolume: 0,
      remainingUsdVolume: this.pass.remainingUsdVolume
    };
  }

  warp(seconds) {
    this.now += seconds;
    return { action: "warp", now: this.now };
  }
}

const demo = new FlowPassDemo();
const steps = [
  demo.swapExactInput(1_000_000, 1_000_000),
  demo.buyPass(),
  demo.swapExactInput(1_000_000, 900_000),
  demo.swapExactInput(20_000_000, 20_000_000),
  demo.swapExactOutput(1_000_000, 1_000_000),
  demo.warp(DURATION_SECONDS + 1),
  demo.swapExactInput(1_000_000, 1_000_000)
];

console.log(JSON.stringify({
  mvpParameters: {
    baseFee: BASE_FEE,
    discountFee: DISCOUNT_FEE,
    passPriceUsdc: PASS_PRICE,
    quotaUsdVolume: QUOTA,
    durationDays: 7,
    lpShareBps: LP_SHARE_BPS,
    treasuryShareBps: BPS_DENOMINATOR - LP_SHARE_BPS
  },
  finalState: {
    pass: demo.pass,
    lpRevenueReserveUsdc: demo.lpRevenueReserve,
    treasuryRevenueReserveUsdc: demo.treasuryRevenueReserve
  },
  steps
}, null, 2));

