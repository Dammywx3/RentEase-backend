import { z } from "zod";

export const userRoleSchema = z.enum(["tenant", "landlord", "agent", "admin"]);

export const registerSchema = z.object({
  organizationId: z.string().uuid(),
  fullName: z.string().min(2).max(100),
  email: z.string().email().max(100),
  phone: z.string().max(20).optional(),
  password: z.string().min(8).max(128),
  role: userRoleSchema.default("tenant"),
});

export const loginSchema = z.object({
  email: z.string().email().max(100),
  password: z.string().min(1).max(128),
});
