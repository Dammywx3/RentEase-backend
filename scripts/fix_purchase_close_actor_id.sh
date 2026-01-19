#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/purchase_close.ts"
[ -f "$FILE" ] || { echo "❌ Missing $FILE"; exit 1; }

cp "$FILE" "$FILE.bak.$(date +%s)"
echo "✅ Backup created: $FILE.bak.*"

# Replace the whole file with a clean, correct version
cat > "$FILE" <<'TS'
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
TS

echo "✅ Rewrote $FILE with correct actorId passing."
echo "==> Confirm payload args line:"
grep -n "purchase_close_complete" -n "$FILE" || true
echo "==> Confirm actorId used:"
grep -n "const actorId" -n "$FILE" || true

echo
echo "NEXT:"
echo "1) Restart server"
echo "2) Create a NEW purchase (because this one is already closed)."
echo "3) Close it via e2e:"
echo "   export DEV_EMAIL='dev_1768638237@rentease.local'"
echo "   export DEV_PASS='Passw0rd!234'"
echo "   ./scripts/e2e_close_purchase.sh <NEW_PURCHASE_ID>"
echo
echo "4) Verify audit changed_by:"
echo "   DB=rentease psql -X -P pager=off -d \"$DB\" -c \"select table_name, record_id::text, operation::text, changed_by::text, created_at from public.audit_logs where table_name='purchase' order by created_at desc limit 5;\""
