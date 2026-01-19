export const VIEWING_TYPES = ["in_person", "virtual"] as const;
export type ViewingType = (typeof VIEWING_TYPES)[number];

export const VIEWING_STATUSES = ["pending", "confirmed", "completed", "cancelled"] as const;
export type ViewingStatus = (typeof VIEWING_STATUSES)[number];
