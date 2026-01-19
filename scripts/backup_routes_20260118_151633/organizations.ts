import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { withRlsTransaction } from "../config/database.js";
import type { PoolClient } from "pg";

const paramsSchema = z.object({
  id: z.string().uuid(),
});

const updateBodySchema = z.object({
  name: z.string().min(2).max(120),
});

type OrgRow = {
  id: string;
  name: string;
  created_at?: string;
  updated_at?: string;
};

async function getOrg(client: PoolClient, id: string): Promise<OrgRow | null> {
  const { rows } = await client.query<OrgRow>(
    `
    SELECT id, name, created_at, updated_at
    FROM organizations
    WHERE id = $1
    LIMIT 1
    `,
    [id]
  );
  return rows[0] ?? null;
}

async function updateOrgName(client: PoolClient, id: string, name: string): Promise<OrgRow | null> {
  const { rows } = await client.query<OrgRow>(
    `
    UPDATE organizations
    SET name = $2, updated_at = now()
    WHERE id = $1
    RETURNING id, name, created_at, updated_at
    `,
    [id, name]
  );
  return rows[0] ?? null;
}

export async function organizationRoutes(app: FastifyInstance) {
  // GET /v1/organizations/:id
  app.get(
    "/organizations/:id",
    { preHandler: [app.authenticate] },
    async (req) => {
      const { id } = paramsSchema.parse((req as any).params);

      const userId = req.user.sub;
      const organizationId = req.user.org;

      const org = await withRlsTransaction(
        { userId, organizationId },
        async (client) => getOrg(client, id)
      );

      if (!org) return { ok: false, error: "NOT_FOUND", message: "Organization not found" };
      return { ok: true, data: org };
    }
  );

  // PUT /v1/organizations/:id
  app.put(
    "/organizations/:id",
    { preHandler: [app.authenticate] },
    async (req) => {
      const { id } = paramsSchema.parse((req as any).params);
      const body = updateBodySchema.parse((req as any).body);

      const userId = req.user.sub;
      const organizationId = req.user.org;

      const updated = await withRlsTransaction(
        { userId, organizationId },
        async (client) => updateOrgName(client, id, body.name)
      );

      if (!updated) return { ok: false, error: "NOT_FOUND", message: "Organization not found" };
      return { ok: true, data: updated };
    }
  );
}
