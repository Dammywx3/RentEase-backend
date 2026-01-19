import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { withRlsTransaction } from "../db/rls_tx.js";

export async function debugPgCtxRoutes(app: FastifyInstance) {
  app.get("/debug/pgctx", { preHandler: [app.authenticate] }, async (req: any) => {
    const ctx = {
      org_id: String(req?.orgId ?? "").trim() || null,
      user_id: String(req?.user?.userId ?? req?.user?.sub ?? "").trim() || null,
      role: (req?.user?.role ?? null) as any,
      event_note: "debug:pgctx",
      hdr_org: String(req?.headers?.["x-organization-id"] ?? "").trim() || null,
      jwt_sub: String(req?.user?.sub ?? "").trim() || null,
    };

    const data = await withRlsTransaction(
      { userId: ctx.user_id ?? "", organizationId: ctx.org_id ?? "", role: ctx.role, eventNote: "debug:pgctx" },
      async (client: PoolClient) => {
        const { rows } = await client.query(`
          select
            current_setting('app.organization_id', true) as org_id,
            current_setting('app.user_id', true) as user_id,
            current_setting('rentease.user_role', true) as role,
            current_setting('app.event_note', true) as event_note,
            current_setting('request.header.x_organization_id', true) as hdr_org,
            current_setting('request.jwt.claim.sub', true) as jwt_sub
        `);
        return rows?.[0] ?? null;
      }
    );

    return { ok: true, data: data ?? ctx };
  });
}
