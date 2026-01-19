export const PAYOUT_STATUSES = ["requested", "processing", "paid", "failed", "cancelled"] as const;
export type PayoutStatus = (typeof PAYOUT_STATUSES)[number];
