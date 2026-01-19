import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { releasePurchaseEscrow } from "../services/purchase_escrow.service.js";

import { setPgContext } from "../db/set_pg_context.js";
import { assertRlsContextWithUser } from "../db/rls_guard.js";

export async function purchaseEscrowRoutes(app: FastifyInstance) {
  // POST /v1/purchases/:id/release-escrow
  // Auth required
  //
  // IMPORTANT:
  // This route accepts BOTH:
  // - no JSON body at all
  // - or { "note": "..." }
  app.post(
    "/:id/release-escrow",
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
      const userId = String(
        (req as any).user?.id || (req as any).user?.userId || (req as any).userId || ""
      ).trim();

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
        await setPgContext(client, {
          userId,
          organizationId,
          role: String((req as any).user?.role ?? "").trim() || null,
          eventNote: "purchase_escrow",
        });
        await assertRlsContextWithUser(client);

        const res = await releasePurchaseEscrow(client, {
          purchaseId: params.id,
          actorUserId: userId, // ✅ REQUIRED by service signature
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