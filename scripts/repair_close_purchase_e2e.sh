#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"
BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"

mkdir -p scripts sql src/routes

echo "==> 1) SQL: Replace safe_audit_log() to support your partitioned audit_logs schema..."
SQL_FILE="sql/2026_01_18_safe_audit_log_partitioned_fix.sql"
cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- This replaces public.safe_audit_log so it works with BOTH schemas:
-- A) "old style" columns: action/entity_type/entity_id/payload/organization_id/actor_id
-- B) your current schema: table_name, record_id, operation (enum), changed_by, change_details
CREATE OR REPLACE FUNCTION public.safe_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_org_id uuid DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  cols text[] := ARRAY[]::text[];
  vals text[] := ARRAY[]::text[];
  sql text;

  op_enum_schema text;
  op_enum_name text;
  chosen_op text;
BEGIN
  -- ------------------------------------------------------------
  -- Case B: partitioned audit_logs (table_name + operation required)
  -- ------------------------------------------------------------
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='audit_logs' AND column_name='table_name'
  )
  AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='audit_logs' AND column_name='operation'
  )
  THEN
    -- Choose an operation label from enum public.audit_operation (or whatever schema owns it)
    SELECT c.udt_schema, c.udt_name
    INTO op_enum_schema, op_enum_name
    FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name='audit_logs' AND c.column_name='operation'
    LIMIT 1;

    -- Prefer UPDATE-like, else fallback to first enum label
    EXECUTE format(
      $q$
      WITH labels AS (
        SELECT e.enumlabel AS label
        FROM pg_type t
        JOIN pg_enum e ON e.enumtypid=t.oid
        JOIN pg_namespace n ON n.oid=t.typnamespace
        WHERE n.nspname=%L AND t.typname=%L
        ORDER BY e.enumsortorder
      )
      SELECT
        COALESCE(
          (SELECT label FROM labels WHERE lower(label) IN ('update','updated','modify','modified','change','changed') LIMIT 1),
          (SELECT label FROM labels LIMIT 1)
        )
      $q$,
      op_enum_schema, op_enum_name
    )
    INTO chosen_op;

    IF chosen_op IS NULL OR chosen_op = '' THEN
      RAISE EXCEPTION 'Could not resolve an audit_operation enum label.';
    END IF;

    -- Build insert dynamically with only columns that exist
    cols := cols || 'table_name';      vals := vals || '$1';
    cols := cols || 'operation';       vals := vals || format('$2::%I.%I', op_enum_schema, op_enum_name);

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='record_id') THEN
      cols := cols || 'record_id';     vals := vals || '$3';
    END IF;

    IF p_actor_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='changed_by') THEN
      cols := cols || 'changed_by';    vals := vals || '$4';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='change_details') THEN
      cols := cols || 'change_details'; vals := vals || '$5';
    END IF;

    sql := format(
      'INSERT INTO public.audit_logs (%s) VALUES (%s)',
      array_to_string(cols, ', '),
      array_to_string(vals, ', ')
    );

    EXECUTE sql
      USING
        COALESCE(NULLIF(trim(p_entity_type),''), 'unknown'), -- table_name
        chosen_op,                                          -- operation enum text
        p_entity_id,                                        -- record_id
        p_actor_id,                                         -- changed_by
        COALESCE(p_payload,'{}'::jsonb);                     -- change_details

    RETURN;
  END IF;

  -- ------------------------------------------------------------
  -- Case A: "old style" audit_logs columns (if present)
  -- ------------------------------------------------------------
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='action') THEN
    cols := cols || 'action'; vals := vals || '$1';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_type') THEN
    cols := cols || 'entity_type'; vals := vals || '$2';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_id') THEN
    cols := cols || 'entity_id'; vals := vals || '$3';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='payload') THEN
    cols := cols || 'payload'; vals := vals || '$4';
  END IF;

  IF p_org_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='organization_id') THEN
    cols := cols || 'organization_id'; vals := vals || '$5';
  END IF;

  IF p_actor_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name IN ('actor_id','user_id','created_by')) THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='actor_id') THEN
      cols := cols || 'actor_id'; vals := vals || '$6';
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='created_by') THEN
      cols := cols || 'created_by'; vals := vals || '$6';
    ELSE
      cols := cols || 'user_id'; vals := vals || '$6';
    END IF;
  END IF;

  IF array_length(cols, 1) IS NULL THEN
    -- If neither schema fits, do nothing (avoid NOT NULL explosions)
    RETURN;
  END IF;

  sql := format(
    'INSERT INTO public.audit_logs (%s) VALUES (%s)',
    array_to_string(cols, ', '),
    array_to_string(vals, ', ')
  );

  EXECUTE sql USING p_action, p_entity_type, p_entity_id, p_payload, p_org_id, p_actor_id;

END;
$$;

COMMIT;
SQL

psql -X -P pager=off -d "$DB" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
echo "✅ safe_audit_log updated."

echo
echo "==> 2) Ensure close route exists: src/routes/purchase_close.ts"
ROUTE_FILE="src/routes/purchase_close.ts"
cp -f "$ROUTE_FILE" "$ROUTE_FILE.bak.$(date +%s)" 2>/dev/null || true

cat > "$ROUTE_FILE" <<'TS'
import type { FastifyInstance } from "fastify";
import { setPgContext } from "../db/set_pg_context.js";

type CloseBody = { note?: string };

function getOrgId(request: any): string {
  return String(request.orgId || "").trim();
}
function getUserId(request: any): string {
  return String(request.user?.id || request.userId || request.sub || "").trim();
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

      const userId = getUserId(request) || null;
      const body = (request.body || {}) as CloseBody;
      const note = typeof body.note === "string" ? body.note.trim() : null;

      const client = await app.pg.connect();
      try {
        await setPgContext(client, {
          organizationId: orgId,
          userId: userId,
          role: (request as any).role || null,
        });

        const { rows } = await client.query(
          `select public.purchase_close_complete($1::uuid, $2::uuid, $3::uuid, $4::text) as result`,
          [purchaseId, orgId, userId, note]
        );

        const result = rows?.[0]?.result ?? null;
        if (result && result.ok === false) {
          return reply.code(400).send({ ok: false, error: result.error || "CLOSE_FAILED", message: result.message || "" });
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

echo "✅ Route written: $ROUTE_FILE"

echo
echo "==> 3) Fix scripts/e2e_close_purchase.sh (autodetect login path + correct audit_logs query)"
E2E="scripts/e2e_close_purchase.sh"
cp -f "$E2E" "$E2E.bak.$(date +%s)" 2>/dev/null || true

cat > "$E2E" <<'EOSH'
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
if [ -z "${EMAIL:-}" ] || [ -z "${PASSWORD:-}" ]; then
  echo "Set credentials first:"
  echo "  export DEV_EMAIL='dev_...@rentease.local'"
  echo "  export DEV_PASS='Passw0rd!234'"
  exit 1
fi

echo "==> Discovering login route from /debug/routes (if available)..."
ROUTES="$(curl -s "$BASE_URL/debug/routes" 2>/dev/null || true)"
LOGIN_PATH="/v1/auth/login"
if echo "$ROUTES" | grep -qE 'auth/.*login \(POST\)'; then
  # Most common: /v1/auth/login
  if echo "$ROUTES" | grep -qE '/v1/.*auth/.*login \(POST\)'; then
    LOGIN_PATH="/v1/auth/login"
  fi
fi
echo "==> Using login endpoint: $LOGIN_PATH"

echo "==> Login..."
LOGIN_JSON="$(curl -s -X POST "$BASE_URL$LOGIN_PATH" \
  -H "Content-Type: application/json" \
  --data-binary "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"

echo "$LOGIN_JSON"

# parse token + org
TMP="/tmp/rentease_close_login_$$.txt"
printf "%s" "$LOGIN_JSON" | node - <<'NODE' > "$TMP"
let raw="";
process.stdin.setEncoding("utf8");
process.stdin.on("data",(c)=>raw+=c);
process.stdin.on("end",()=>{
  try{
    const j=JSON.parse(raw||"{}");
    const token=j.token || j.accessToken || j.access_token || (j.data && (j.data.token || j.data.accessToken || j.data.access_token)) || "";
    const org=(j.user && (j.user.organization_id || j.user.organizationId)) || (j.data && j.data.user && (j.data.user.organization_id || j.data.user.organizationId)) || j.org || "";
    const uid=(j.user && (j.user.id||j.user.userId)) || (j.data && j.data.user && (j.data.user.id||j.data.user.userId)) || "";
    if(!token){ console.log(""); console.log(""); console.log(""); process.exit(0); }
    console.log(token);
    console.log(org);
    console.log(uid);
  }catch(e){
    console.log(""); console.log(""); console.log("");
  }
});
NODE

TOKEN="$(sed -n '1p' "$TMP" | tr -d '\r')"
ORG_ID="$(sed -n '2p' "$TMP" | tr -d '\r')"
USER_ID="$(sed -n '3p' "$TMP" | tr -d '\r')"
rm -f "$TMP"

if [ -z "${TOKEN:-}" ] || [ -z "${ORG_ID:-}" ]; then
  echo "❌ Login failed or route missing. Run:"
  echo "  curl -s $BASE_URL/debug/routes | sed -n '1,200p'"
  exit 2
fi

echo "==> Token length: ${#TOKEN}"
echo "==> Org ID: $ORG_ID"
[ -n "${USER_ID:-}" ] && echo "==> User ID: $USER_ID"

echo
echo "==> Close purchase..."
curl -s -i -X POST "$BASE_URL/v1/purchases/$PURCHASE_ID/close" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -H "Content-Type: application/json" \
  --data-binary '{}' | sed -n '1,220p'

echo
echo "==> Verify purchase status..."
psql -X -P pager=off -d "$DB" -c "
select id::text, status::text, closed_at, updated_at
from public.property_purchases
where id::text='${PURCHASE_ID}'
limit 1;
" || true

echo
echo "==> Verify audit log (your schema: table_name/operation/record_id/change_details)..."
psql -X -P pager=off -d "$DB" -c "
select
  table_name,
  operation::text as operation,
  record_id::text as record_id,
  changed_by::text as changed_by,
  change_details,
  created_at
from public.audit_logs
where record_id::text='${PURCHASE_ID}'
order by created_at desc
limit 10;
" || true

echo
echo "✅ Done."
EOSH

chmod +x "$E2E"
echo "✅ Updated: $E2E"

echo
echo "==> 4) Rebuild routes index (preserving registerRoutes) ..."
if [ -x "./scripts/rebuild_routes_index.sh" ]; then
  ./scripts/rebuild_routes_index.sh
else
  echo "⚠️ scripts/rebuild_routes_index.sh not found/executable. Skipping."
fi

echo
echo "==> 5) Quick route visibility check (after you restart server):"
echo "   curl -s $BASE_URL/debug/routes | grep -n \"auth\" | head"
echo "   curl -s $BASE_URL/debug/routes | grep -n \"purchases\" | head"

echo
echo "✅ Repair complete."
echo
echo "NEXT:"
echo "1) Restart your server (this is required for new routes to load)"
echo "2) Run:"
echo "   export DEV_EMAIL='dev_1768638237@rentease.local'"
echo "   export DEV_PASS='Passw0rd!234'"
echo "   ./scripts/e2e_close_purchase.sh 5ae53ce5-433d-4966-a1e8-edb8d0f6d1ae"
