// src/routes/me.ts
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;

  if (!userId) throw new Error("ME_CTX_MISSING_USER");
  if (!organizationId) throw new Error("ME_CTX_MISSING_ORG");

  return { userId, organizationId, role };
}

export async function meRoutes(app: FastifyInstance) {
  // NOTE: routes/index.ts already registers this plugin with prefix "/me"
  // So inside here we use "/" (NOT "/me") to avoid "/v1/me/me"
  app.get("/", { preHandler: [app.authenticate] }, async (req: any) => {
    const ctx = getCtx(req);

    const me = await withRlsTransaction(
      {
        userId: ctx.userId,
        organizationId: ctx.organizationId,
        role: ctx.role,
        eventNote: "me:get",
      },
      async (client: PoolClient) => {
        const { rows } = await client.query(
          `
          SELECT
            id,
            organization_id,
            full_name,
            email,
            phone,
            role,
            verified_status,
            created_at,
            updated_at
          FROM public.users
          WHERE id = $1
          LIMIT 1
          `,
          [ctx.userId]
        );

        return rows[0] ?? null;
      }
    );

    return { ok: true, data: me };
  });
}