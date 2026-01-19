export const PROPERTY_TYPES = ["rent", "sale", "short_lease", "long_lease"] as const;
export type PropertyType = (typeof PROPERTY_TYPES)[number];

export const PROPERTY_STATUSES = ["available", "occupied", "pending", "maintenance", "unavailable"] as const;
export type PropertyStatus = (typeof PROPERTY_STATUSES)[number];

export const PROPERTY_MEDIA = {
  MAX_FILES_PER_PROPERTY: 50,
  ALLOWED_MIME: ["image/jpeg", "image/png", "image/webp", "video/mp4"] as const,
  MAX_FILE_SIZE_BYTES: 25 * 1024 * 1024,
} as const;
