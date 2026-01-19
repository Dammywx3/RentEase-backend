import type { FastifyInstance } from "fastify";
import { setPgContext } from "../db/set_pg_context.js";

type CloseBody = { note?: string };

function getOrgId(request: any): string {
  return String(request.orgId || "").trim();
}

// prefer request.user.id from auth decorator; fallback to known shapes
function getActorId(request: any): string {
  return String(
    request.user?.id ||
      request.userId ||
      request.user?.userId ||
      request.sub ||
      request.user?.sub ||
      ""
  ).trim();
}

export async function purchaseCloseRoutes(app: FastifyInstance) {
  // POST /v1/purchases/:id/close
  app.post(
    "/:id/close",
    { preHandler: [app.authenticate] },
    async (request, reply) => {
      const purchaseId = String((request.params as any)?.id || "").trim();
      if (!purchaseId) {
        return reply.code(400).send({ ok: false, error: "PURCHASE_ID_REQUIRED" });
      }

      const orgId = getOrgId(request);
      if (!orgId) {
        return reply.code(400).send({ ok: false, error: "ORG_REQUIRED" });
      }

      const actorId = getActorId(request);
      if (!actorId) {
        return reply.code(401).send({ ok: false, error: "AUTH_REQUIRED", message: "Missing actor id from auth" });
      }

      const body = (request.body || {}) as CloseBody;
      const note = typeof body.note === "string" ? body.note.trim() : null;

      const client = await app.pg.connect();
      try {
        await setPgContext(client, {
          organizationId: orgId,
          userId: actorId, // for RLS context
          role: (request as any).role || null,
        });

        // IMPORTANT: pass actorId as arg #3 so safe_audit_log writes changed_by
        const { rows } = await client.query(
          `select public.purchase_close_complete($1::uuid, $2::uuid, $3::uuid, $4::text) as result`,
          [purchaseId, orgId, actorId, note]
        );

        const result = rows?.[0]?.result ?? null;
        if (result && result.ok === false) {
          return reply.code(400).send({
            ok: false,
            error: result.error || "CLOSE_FAILED",
            message: result.message || "",
          });
        }

        return reply.send({ ok: true, data: result || { ok: true } });
      } catch (e: any) {
        request.log.error(e);
        return reply.code(400).send({ ok: false, error: "CLOSE_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );
}
