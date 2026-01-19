import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";

import { withRlsTransaction } from "../db/rls_tx.js";

function getCtx(req: any) {
  const userId = String(req?.user?.userId ?? "").trim();
  const organizationId = String(req?.orgId ?? "").trim();
  const role = (req?.user?.role ?? null) as any;

  if (!userId) throw new Error("debug_pgctx: missing req.user.userId");
  if (!organizationId) throw new Error("debug_pgctx: missing req.orgId");

  return { userId, organizationId, role };
}

export async function debugPgCtxRoutes(app: FastifyInstance) {
  app.get("/debug/pgctx", { preHandler: [app.authenticate] }, async (req: any) => {
    const ctx = getCtx(req);

    const data = await withRlsTransaction(
      { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role, eventNote: "debug:pgctx" },
      async (client: PoolClient) => {
        const { rows } = await client.query(`
          SELECT
            current_setting('app.organization_id', true) AS org_id,
            current_setting('app.user_id', true) AS user_id,
            current_setting('app.user_role', true) AS role,
            current_setting('app.event_note', true) AS event_note,
            current_setting('request.header.x_organization_id', true) AS hdr_org,
            current_setting('request.jwt.claim.sub', true) AS jwt_sub
        `);

        return rows[0] ?? null;
      }
    );

    return { ok: true, data };
  });
}
