export const DISPUTE_STATUSES = ["open", "under_review", "resolved", "rejected", "closed"] as const;
export type DisputeStatus = (typeof DISPUTE_STATUSES)[number];
