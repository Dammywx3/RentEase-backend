import { z } from "zod";

export const OrgIdSchema = z.string().uuid();

export const UpdateOrganizationBodySchema = z.object({
  name: z.string().min(2).max(100),
});

export type UpdateOrganizationBody = z.infer<typeof UpdateOrganizationBodySchema>;
