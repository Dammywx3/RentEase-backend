// src/config/fees.config.ts
export type PaymentKind = "rent" | "buy" | "subscription";

export type FeeContext = {
  paymentKind: PaymentKind;
  amount: number;     // major units (e.g. 2000.00 NGN)
  currency: string;   // "USD", "NGN", etc
};

export type FeeSplit = {
  platformFee: number; // >= 0
  payeeNet: number;    // >= 0
  pctUsed: number;
};

// SINGLE SOURCE OF TRUTH
export const FEES = {
  rent: { platformFeePct: 2.5, minPlatformFee: 0, maxPlatformFee: Number.POSITIVE_INFINITY },
  buy: { platformFeePct: 2.5, minPlatformFee: 0, maxPlatformFee: Number.POSITIVE_INFINITY },
  subscription: { platformFeePct: 0, minPlatformFee: 0, maxPlatformFee: Number.POSITIVE_INFINITY },
} as const;

function isFiniteNumber(n: unknown): n is number {
  return typeof n === "number" && Number.isFinite(n);
}

export function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

export function computePlatformFeeSplit(ctx: FeeContext): FeeSplit {
  if (!ctx || !isFiniteNumber(ctx.amount) || ctx.amount < 0) {
    // fail closed — do not charge fee on invalid amount
    return { platformFee: 0, payeeNet: 0, pctUsed: 0 };
  }

  const rules = FEES[ctx.paymentKind] ?? FEES.rent;
  const pct = rules.platformFeePct;

  let fee = round2((ctx.amount * pct) / 100);

  if (fee < rules.minPlatformFee) fee = rules.minPlatformFee;
  if (fee > rules.maxPlatformFee) fee = rules.maxPlatformFee;

  // Never allow fee to exceed amount
  if (fee > ctx.amount) fee = round2(ctx.amount);

  const net = round2(Math.max(0, ctx.amount - fee));

  return {
    platformFee: fee,
    payeeNet: net,
    pctUsed: pct,
  };
}