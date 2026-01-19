import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { releasePurchaseEscrow } from "../services/purchase_escrow.service.js";

import { setPgContext } from "../db/set_pg_context.js";

export async function purchaseEscrowRoutes(app: FastifyInstance) {
  // POST /v1/purchases/:id/release-escrow
  // Auth required
  //
  // IMPORTANT:
  // This route accepts BOTH:
  // - no JSON body at all
  // - or { "note": "..." }
  app.post(
    "/purchases/:id/release-escrow",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const params = z.object({ id: z.string().uuid() }).parse((req as any).params);

      // Body is OPTIONAL (fix for "Body cannot be empty when content-type is application/json")
      const body = z
        .object({
          note: z.string().min(1).optional(),
        })
        .optional()
        .parse((req as any).body);

      const organizationId = String((req as any).orgId ?? "").trim();
      const userId = String((req as any).user?.userId ?? "").trim();

      if (!organizationId) {
        return reply
          .code(400)
          .send({ ok: false, error: "ORG_REQUIRED", message: "Missing orgId from auth middleware" });
      }
      if (!userId) {
        return reply
          .code(401)
          .send({ ok: false, error: "UNAUTHORIZED", message: "Missing authenticated user" });
      }

      // @ts-ignore - fastify-postgres decorates app.pg
      const client = await app.pg.connect();
      try {
        await client.query("BEGIN");

        await client.query("SET LOCAL TIME ZONE 'UTC'");
        // RLS context
        await client.query("select set_config('app.organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.header.x_organization_id', $1, true)", [organizationId]);
        await client.query("select set_config('request.jwt.claim.sub', $1, true)", [userId]);
        await client.query("select set_config('app.user_id', $1, true)", [userId]);

        const res = await releasePurchaseEscrow(client, {
          purchaseId: params.id,
          note: body?.note ?? "Closing complete, released escrow",
        });

        await client.query("COMMIT");

        if (!res.ok) {
          return reply.code(400).send({ ok: false, error: res.error, message: res.message });
        }

        return reply.send({ ok: true, data: res });
      } catch (e: any) {
        try {
          await client.query("ROLLBACK");
        } catch {}
        return reply.code(500).send({
          ok: false,
          error: "SERVER_ERROR",
          message: e?.message ?? String(e),
        });
      } finally {
        client.release();
      }
    }
  );
}
