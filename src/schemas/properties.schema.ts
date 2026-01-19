import { z } from "zod";

// Matches your DB enums
export const propertyTypeEnum = z.enum(["rent", "sale", "short_lease", "long_lease"]);
export const propertyStatusEnum = z.enum(["available", "occupied", "pending", "maintenance", "unavailable"]);
export const verifiedStatusEnum = z.enum(["pending", "verified", "rejected", "suspended"]);

export const createPropertySchema = z.object({
  ownerId: z.string().uuid().optional(), // optional because DB allows external owner (chk_owner_present)
  ownerExternalName: z.string().min(1).max(255).optional(),
  ownerExternalPhone: z.string().min(3).max(30).optional(),
  ownerExternalEmail: z.string().email().optional(),
  defaultAgentId: z.string().uuid().optional(),

  title: z.string().min(2).max(255),
  description: z.string().max(50_000).optional(),

  type: propertyTypeEnum,
  basePrice: z.number().positive(),
  currency: z.string().length(3).optional(), // if omitted => DB default 'USD'

  addressLine1: z.string().max(255).optional(),
  addressLine2: z.string().max(255).optional(),
  city: z.string().max(100).optional(),
  state: z.string().max(100).optional(),
  country: z.string().max(100).optional(),
  postalCode: z.string().max(20).optional(),

  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional(),

  bedrooms: z.number().int().min(0).optional(),
  bathrooms: z.number().int().min(0).optional(),
  squareMeters: z.number().positive().optional(),
  yearBuilt: z.number().int().min(1000).max(3000).optional(),

  amenities: z.array(z.string().min(1)).optional(),

  // ✅ IMPORTANT: optional (NOT nullable). If omitted => DB defaults apply.
  status: propertyStatusEnum.optional(),
  verificationStatus: verifiedStatusEnum.optional(),

  slug: z.string().max(300).optional(),
});

export const listPropertiesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  offset: z.coerce.number().int().min(0).default(0),
  status: propertyStatusEnum.optional(),
  type: propertyTypeEnum.optional(),
  city: z.string().max(100).optional(),
});

export const patchPropertySchema = z.object({
  ownerId: z.string().uuid().nullable().optional(),
  ownerExternalName: z.string().min(1).max(255).nullable().optional(),
  ownerExternalPhone: z.string().min(3).max(30).nullable().optional(),
  ownerExternalEmail: z.string().email().nullable().optional(),
  defaultAgentId: z.string().uuid().nullable().optional(),

  title: z.string().min(2).max(255).optional(),
  description: z.string().max(50_000).nullable().optional(),

  type: propertyTypeEnum.optional(),
  basePrice: z.number().positive().optional(),
  currency: z.string().length(3).nullable().optional(),

  addressLine1: z.string().max(255).nullable().optional(),
  addressLine2: z.string().max(255).nullable().optional(),
  city: z.string().max(100).nullable().optional(),
  state: z.string().max(100).nullable().optional(),
  country: z.string().max(100).nullable().optional(),
  postalCode: z.string().max(20).nullable().optional(),

  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),

  bedrooms: z.number().int().min(0).nullable().optional(),
  bathrooms: z.number().int().min(0).nullable().optional(),
  squareMeters: z.number().positive().nullable().optional(),
  yearBuilt: z.number().int().min(1000).max(3000).nullable().optional(),

  amenities: z.array(z.string().min(1)).nullable().optional(),

  status: propertyStatusEnum.nullable().optional(),
  verificationStatus: verifiedStatusEnum.nullable().optional(),

  slug: z.string().max(300).nullable().optional(),
});
