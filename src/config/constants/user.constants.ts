export const USER_ROLES = ["tenant", "landlord", "agent", "admin"] as const;
export type UserRole = (typeof USER_ROLES)[number];

export const VERIFIED_STATUSES = ["pending", "verified", "rejected", "suspended"] as const;
export type VerifiedStatus = (typeof VERIFIED_STATUSES)[number];

export const PASSWORD_POLICY = {
  MIN_LEN: 8,
  MAX_LEN: 72, // bcrypt practical limit
  REQUIRE_UPPER: true,
  REQUIRE_LOWER: true,
  REQUIRE_NUMBER: true,
  REQUIRE_SYMBOL: true,
} as const;

export const LOGIN_SECURITY = {
  MAX_FAILED_ATTEMPTS: 10,
  LOCK_MINUTES: 15,
} as const;
