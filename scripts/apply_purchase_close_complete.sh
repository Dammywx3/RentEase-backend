#!/usr/bin/env bash
set -euo pipefail

echo "==> Writing SQL migration..."
SQL_FILE="sql/2026_01_18_purchase_close_complete.sql"
mkdir -p sql

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- 1) Audit log table (create if missing)
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT rentease_uuid(),
  organization_id uuid NOT NULL DEFAULT current_organization_uuid() REFERENCES public.organizations(id),
  actor_user_id uuid REFERENCES public.users(id),
  action text NOT NULL,
  entity_type text,
  entity_id uuid,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_org_created ON public.audit_logs(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id, created_at DESC);

-- 2) Idempotency guard for escrow release:
-- Ensure only ONE escrow release debit exists per purchase (prevents double-close)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema='public' AND table_name='wallet_transactions'
  ) THEN
    -- You may already have a unique constraint; add only if missing
    IF NOT EXISTS (
      SELECT 1
      FROM pg_constraint c
      JOIN pg_class t ON t.oid=c.conrelid
      JOIN pg_namespace n ON n.oid=t.relnamespace
      WHERE n.nspname='public'
        AND t.relname='wallet_transactions'
        AND c.conname='uniq_wallet_txn_purchase_release'
    ) THEN
      -- This assumes txn_type exists and uses 'debit_escrow' for release.
      -- Also assumes reference_type='purchase' and reference_id=purchase_id are stored.
      EXECUTE $q$
        CREATE UNIQUE INDEX uniq_wallet_txn_purchase_release
        ON public.wallet_transactions(reference_type, reference_id, txn_type, amount, currency)
        WHERE reference_type='purchase' AND txn_type='debit_escrow'
      $q$;
    END IF;
  END IF;
END $$;

COMMIT;
SQL

echo "==> Writing service: src/services/purchase_close.service.ts"
cat > src/services/purchase_close.service.ts <<'TS'
import type { PoolClient } from "pg";

type ClosePurchaseResult =
  | { ok: true; alreadyClosed: boolean; purchaseId: string }
  | { ok: false; error: string; message?: string };

export async function closePurchaseComplete(
  client: PoolClient,
  args: {
    organizationId: string;
    purchaseId: string;
    actorUserId: string;
  }
): Promise<ClosePurchaseResult> {
  const { organizationId, purchaseId, actorUserId } = args;

  // 1) Load purchase + ensure exists
  const p = await client.query(
    `
    SELECT id, organization_id, status::text AS status
    FROM public.property_purchases
    WHERE id = $1 AND organization_id = $2 AND deleted_at IS NULL
    LIMIT 1
    `,
    [purchaseId, organizationId]
  );

  if (p.rowCount === 0) {
    return { ok: false, error: "PURCHASE_NOT_FOUND", message: "Purchase not found" };
  }

  const status = String(p.rows[0].status ?? "");

  // Treat these as "closed" already (adjust to your enum)
  const alreadyClosed = ["closed", "completed", "complete"].includes(status);

  // 2) Mark purchase closed (idempotent)
  // If your schema uses a different status enum, adjust the status value here.
  if (!alreadyClosed) {
    await client.query(
      `
      UPDATE public.property_purchases
      SET status = 'closed',
          closed_at = COALESCE(closed_at, now()),
          updated_at = now()
      WHERE id = $1 AND organization_id = $2
      `,
      [purchaseId, organizationId]
    );
  }

  // 3) Audit log
  await client.query(
    `
    INSERT INTO public.audit_logs (
      organization_id, actor_user_id, action, entity_type, entity_id, payload
    ) VALUES ($1, $2, $3, $4, $5, $6::jsonb)
    `,
    [
      organizationId,
      actorUserId,
      "purchase.close_complete",
      "purchase",
      purchaseId,
      JSON.stringify({ purchaseId, previousStatus: status }),
    ]
  );

  return { ok: true, alreadyClosed, purchaseId };
}
TS

echo "==> Writing route: src/routes/purchase_close.ts"
cat > src/routes/purchase_close.ts <<'TS'
import type { FastifyInstance } from "fastify";
import { closePurchaseComplete } from "../services/purchase_close.service.js";

export async function purchaseCloseRoutes(app: FastifyInstance) {
  // POST /v1/purchases/:id/close
  app.post(
    "/purchases/:id/close",
    {
      // same auth style as your other protected endpoints
      preHandler: (app as any).authenticate,
      schema: {
        params: {
          type: "object",
          required: ["id"],
          properties: { id: { type: "string" } },
        },
      },
    },
    async (request, reply) => {
      const purchaseId = (request.params as any).id as string;

      const orgId =
        String((request.headers["x-organization-id"] as any) ?? "") ||
        String((request as any).user?.org ?? "") ||
        String((request as any).user?.organization_id ?? "");

      const actorUserId =
        String((request as any).user?.sub ?? "") ||
        String((request as any).user?.id ?? "");

      if (!orgId) {
        return reply.code(400).send({ ok: false, error: "ORG_ID_MISSING" });
      }
      if (!actorUserId) {
        return reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Missing user" });
      }

      // @ts-ignore fastify-postgres decorates app.pg
      const client = await app.pg.connect();
      try {
        await client.query("BEGIN");

        const res = await closePurchaseComplete(client, {
          organizationId: orgId,
          purchaseId,
          actorUserId,
        });

        if (!res.ok) {
          await client.query("ROLLBACK");
          return reply.code(400).send({ ok: false, error: res.error, message: res.message });
        }

        await client.query("COMMIT");
        return reply.send({ ok: true, data: res });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        app.log.error(e, "purchase close failed");
        return reply.code(500).send({ ok: false, error: "INTERNAL_ERROR" });
      } finally {
        client.release();
      }
    }
  );
}
TS

echo "==> Patching src/routes/index.ts to register purchaseCloseRoutes..."
ROUTES_INDEX="src/routes/index.ts"

if [ ! -f "$ROUTES_INDEX" ]; then
  echo "❌ Missing $ROUTES_INDEX"
  exit 1
fi

# add import if missing
grep -q "purchaseCloseRoutes" "$ROUTES_INDEX" || \
  perl -0777 -i -pe 's/(import .*;\n)/$1import { purchaseCloseRoutes } from ".\/purchase_close.js";\n/s' "$ROUTES_INDEX"

# register inside /v1 block (best-effort: append after purchaseEscrowRoutes if found, else append near end)
if grep -q "purchaseEscrowRoutes" "$ROUTES_INDEX"; then
  perl -0777 -i -pe 's/(await\s+app\.register\(purchaseEscrowRoutes\);\s*\n)/$1    await app.register(purchaseCloseRoutes);\n/s' "$ROUTES_INDEX"
else
  perl -0777 -i -pe 's/(\/\*\s*register routes\s*\*\/\s*\n)/$1    await app.register(purchaseCloseRoutes);\n/s' "$ROUTES_INDEX" || true
fi

echo "==> Writing E2E script: scripts/e2e_close_purchase.sh"
cat > scripts/e2e_close_purchase.sh <<'EOSH'
#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"
DB="${DB:-rentease}"

EMAIL="${DEV_EMAIL:-${EMAIL:-}}"
PASSWORD="${DEV_PASS:-${PASSWORD:-}}"

PURCHASE_ID="${1:-}"
if [ -z "$PURCHASE_ID" ]; then
  echo "Usage: ./scripts/e2e_close_purchase.sh <PURCHASE_ID>"
  exit 1
fi

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Set DEV_EMAIL + DEV_PASS (or EMAIL + PASSWORD)."
  exit 1
fi

echo "==> Login..."
LOGIN_JSON="$(curl -s -X POST "$BASE_URL/v1/auth/login" \
  -H "Content-Type: application/json" \
  --data-binary "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"

echo "$LOGIN_JSON"

OUT="/tmp/rentease_login_$$.txt"
printf "%s" "$LOGIN_JSON" | node - <<'NODE' > "$OUT"
let raw=""; process.stdin.setEncoding("utf8");
process.stdin.on("data",c=>raw+=c);
process.stdin.on("end",()=>{
  const j=JSON.parse(raw||"{}");
  if(j.ok===false){ console.error("LOGIN_FAILED"); process.exit(10); }
  process.stdout.write((j.token||"")+"\n"+(j.user?.organization_id||"")+"\n"+(j.user?.id||"")+"\n");
});
NODE

TOKEN="$(sed -n '1p' "$OUT" | tr -d '\r')"
ORG_ID="$(sed -n '2p' "$OUT" | tr -d '\r')"
rm -f "$OUT"

echo "==> Close purchase..."
curl -s -i -X POST "$BASE_URL/v1/purchases/$PURCHASE_ID/close" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -H "Content-Type: application/json" \
  --data-binary '{}' | sed -n '1,200p'

echo
echo "==> Verify purchase status..."
psql -X -P pager=off -d "$DB" -c "
select id::text, status::text, closed_at, updated_at
from public.property_purchases
where id::text='${PURCHASE_ID}'
limit 1;
" || true

echo
echo "==> Verify audit log..."
psql -X -P pager=off -d "$DB" -c "
select action, entity_type, entity_id::text, payload, created_at
from public.audit_logs
where entity_type='purchase' and entity_id::text='${PURCHASE_ID}'
order by created_at desc
limit 5;
" || true

echo "✅ Done."
EOSH

chmod +x scripts/e2e_close_purchase.sh

echo
echo "✅ Done creating files + patching routes."
echo
echo "NEXT STEPS:"
echo "1) Apply SQL migration:"
echo "   DB=rentease psql -X -P pager=off -d \"\$DB\" -f $SQL_FILE"
echo
echo "2) Restart server"
echo
echo "3) Run:"
echo "   export DEV_EMAIL='dev_...@rentease.local'"
echo "   export DEV_PASS='Passw0rd!234'"
echo "   ./scripts/e2e_close_purchase.sh <PURCHASE_ID>"
