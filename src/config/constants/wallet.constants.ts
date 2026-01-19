export const WALLET_TX_DIRECTIONS = ["credit", "debit"] as const;
export type WalletTxDirection = (typeof WALLET_TX_DIRECTIONS)[number];

export const WALLET_TX_REASONS = [
  "rent_payment",
  "commission",
  "refund",
  "payout",
  "adjustment",
] as const;

export type WalletTxReason = (typeof WALLET_TX_REASONS)[number];
