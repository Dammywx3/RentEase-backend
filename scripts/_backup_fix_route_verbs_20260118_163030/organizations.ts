import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

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

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;
  return { userId, organizationId, role };
}

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
  app.get("/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = paramsSchema.parse((req as any).params);
    const ctx = getCtx(req);

    const org = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `org:get:${id}` },
      async (client) => getOrg(client, id)
    );

    if (!org) return { ok: false, error: "NOT_FOUND", message: "Organization not found" };
    return { ok: true, data: org };
  });

  // PUT /v1/organizations/:id
  app.get("/:id", { preHandler: [app.authenticate] }, async (req: any) => {
    const { id } = paramsSchema.parse((req as any).params);
    const body = updateBodySchema.parse((req as any).body);
    const ctx = getCtx(req);

    const updated = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: `org:put:${id}` },
      async (client) => updateOrgName(client, id, body.name)
    );

    if (!updated) return { ok: false, error: "NOT_FOUND", message: "Organization not found" };
    return { ok: true, data: updated };
  });
}
