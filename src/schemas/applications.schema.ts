import { z } from "zod";

export const applicationStatusSchema = z.enum([
  "pending",
  "approved",
  "rejected",
  "withdrawn",
]);

export const createApplicationBodySchema = z.object({
  listingId: z.string().uuid(),
  propertyId: z.string().uuid(),

  message: z.string().max(5000).optional(),
  monthlyIncome: z.number().positive().optional(),
  moveInDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, "moveInDate must be YYYY-MM-DD").optional(),

  status: applicationStatusSchema.optional(),
});

export const listApplicationsQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10),
  offset: z.coerce.number().int().min(0).default(0),

  listingId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  applicantId: z.string().uuid().optional(),
  status: applicationStatusSchema.optional(),
});

export const patchApplicationBodySchema = z.object({
  status: applicationStatusSchema.optional(),
  message: z.string().max(5000).nullable().optional(),
  monthlyIncome: z.number().positive().nullable().optional(),
  moveInDate: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "moveInDate must be YYYY-MM-DD")
    .nullable()
    .optional(),
});
