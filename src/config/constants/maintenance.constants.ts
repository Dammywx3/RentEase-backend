export const MAINTENANCE_STATUSES = ["open", "assigned", "in_progress", "completed", "cancelled"] as const;
export type MaintenanceStatus = (typeof MAINTENANCE_STATUSES)[number];

export const MAINTENANCE_PRIORITIES = ["low", "medium", "high", "urgent"] as const;
export type MaintenancePriority = (typeof MAINTENANCE_PRIORITIES)[number];
