export const TENANCY_STATUSES = ["active", "ended", "terminated", "pending_start"] as const;
export type TenancyStatus = (typeof TENANCY_STATUSES)[number];

export const RENT = {
  GRACE_DAYS: 3,
} as const;
