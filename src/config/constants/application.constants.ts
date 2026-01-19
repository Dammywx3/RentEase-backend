export const APPLICATION_STATUSES = [
  "submitted",
  "under_review",
  "approved",
  "rejected",
  "withdrawn",
] as const;

export type ApplicationStatus = (typeof APPLICATION_STATUSES)[number];
