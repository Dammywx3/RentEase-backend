import { z } from "zod";

export const viewingModeSchema = z.enum(["in_person", "virtual"]);
export const viewingStatusSchema = z.enum(["pending", "confirmed", "completed", "cancelled"]);

export const createViewingBodySchema = z.object({
  listingId: z.string().uuid(),
  propertyId: z.string().uuid(),
  scheduledAt: z.string().datetime({ offset: true }),
  viewMode: viewingModeSchema.optional(),
  notes: z.string().max(5000).optional(),
  status: viewingStatusSchema.optional(),
});

export const listViewingsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10),
  offset: z.coerce.number().int().min(0).default(0),
  listingId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  tenantId: z.string().uuid().optional(),
  status: viewingStatusSchema.optional(),
});

export const patchViewingBodySchema = z.object({
  scheduledAt: z.string().datetime({ offset: true }).optional(),
  viewMode: viewingModeSchema.optional(),
  notes: z.string().max(5000).nullable().optional(),
  status: viewingStatusSchema.optional(),
});
