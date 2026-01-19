#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# RentEase - Purchases Actor Context + (Optional) RLS Pack
# Creates:
#  - public.current_app_user_uuid()
#  - public.current_app_org_uuid()
# Updates trigger:
#  - public.trg_property_purchases_transition_and_log() uses actor priority:
#      app.user_id -> refunded_by -> buyer_id
# Optional WITH_RLS=1:
#  - enables RLS on property_purchases + purchase_events
#  - adds basic org isolation policies (uses current_app_org_uuid)
#
# ALSO patches backend to set DB session vars per request:
#  - app.user_id, app.organization_id via set_config
#
# Usage:
#   chmod +x scripts/fix_all_purchase_actor_context_and_rls.sh
#   DB_NAME=rentease bash scripts/fix_all_purchase_actor_context_and_rls.sh
#
# Optional:
#   WITH_RLS=1 DB_NAME=rentease bash scripts/fix_all_purchase_actor_context_and_rls.sh
# ============================================================

DB_NAME="${DB_NAME:-rentease}"
WITH_RLS="${WITH_RLS:-0}"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ Missing required command: $1"
    exit 127
  }
}

need_cmd psql
need_cmd node
need_cmd npm

echo "==> ROOT=$ROOT"
echo "==> DB_NAME=$DB_NAME"
echo "==> WITH_RLS=$WITH_RLS"

SQL_FILE="$ROOT/scripts/.tmp_fix_all_purchase_actor_context_and_rls.$STAMP.sql"

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- Helpers from session settings
CREATE OR REPLACE FUNCTION public.current_app_user_uuid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.user_id', true), '')::uuid
$$;

CREATE OR REPLACE FUNCTION public.current_app_org_uuid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.organization_id', true), '')::uuid
$$;

-- Patch trigger function to use actor priority:
-- 1) app.user_id (set by API using set_config)
-- 2) refunded_by
-- 3) buyer_id
CREATE OR REPLACE FUNCTION public.trg_property_purchases_transition_and_log()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  old_status text;
  new_status text;
  old_pay text;
  new_pay text;
  actor uuid;
BEGIN
  old_status := COALESCE(OLD.status::text, NULL);
  new_status := COALESCE(NEW.status::text, NULL);

  old_pay := COALESCE(OLD.payment_status::text, NULL);
  new_pay := COALESCE(NEW.payment_status::text, NULL);

  actor := COALESCE(
    public.current_app_user_uuid(),
    NEW.refunded_by,
    NEW.buyer_id
  );

  -- enforce transitions if function exists
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
             WHERE n.nspname='public' AND p.proname='assert_purchase_transition') THEN
    PERFORM public.assert_purchase_transition(old_status, new_status, old_pay, new_pay);
  END IF;

  -- log payment events
  IF old_pay IS DISTINCT FROM new_pay THEN
    IF new_pay = 'paid' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'paid',
        actor,
        old_pay, new_pay,
        'payment_status changed to paid',
        jsonb_build_object('source','trigger')
      );
    ELSIF new_pay = 'refunded' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'refunded',
        actor,
        old_pay, new_pay,
        'payment_status changed to refunded',
        jsonb_build_object(
          'source','trigger',
          'refund_method', NEW.refund_method,
          'refund_payment_id', NEW.refund_payment_id,
          'refunded_reason', NEW.refunded_reason
        )
      );
    ELSE
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'status_changed',
        actor,
        old_pay, new_pay,
        'payment_status changed',
        jsonb_build_object('source','trigger')
      );
    END IF;
  END IF;

  -- log business status events
  IF old_status IS DISTINCT FROM new_status THEN
    INSERT INTO public.purchase_events(
      organization_id, purchase_id, event_type, actor_user_id,
      from_status, to_status, note, metadata
    ) VALUES (
      NEW.organization_id, NEW.id, 'status_changed',
      actor,
      old_status, new_status,
      'status changed',
      jsonb_build_object('source','trigger')
    );

    IF new_status = 'completed' THEN
      INSERT INTO public.purchase_events(
        organization_id, purchase_id, event_type, actor_user_id,
        from_status, to_status, note, metadata
      ) VALUES (
        NEW.organization_id, NEW.id, 'completed',
        actor,
        old_status, new_status,
        'purchase completed',
        jsonb_build_object('source','trigger')
      );
    END IF;
  END IF;

  RETURN NEW;
END $$;

COMMIT;
SQL

echo "==> Applying SQL: $SQL_FILE"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE" >/dev/null
echo "✅ DB actor-context patch applied"

if [[ "$WITH_RLS" == "1" ]]; then
  echo "==> Enabling RLS + org policies..."
  psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
BEGIN;

ALTER TABLE public.property_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='property_purchases' AND policyname='purchases_org_isolation_app'
  ) THEN
    CREATE POLICY purchases_org_isolation_app
    ON public.property_purchases
    USING (organization_id = public.current_app_org_uuid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='purchase_events' AND policyname='purchase_events_org_isolation_app'
  ) THEN
    CREATE POLICY purchase_events_org_isolation_app
    ON public.purchase_events
    USING (organization_id = public.current_app_org_uuid());
  END IF;
END $$;

COMMIT;
SQL
  echo "✅ RLS enabled + basic org policies created"
else
  echo "ℹ️ Skipping RLS (set WITH_RLS=1 when ready)"
fi

# ============================================================
# Patch backend: set app.user_id + app.organization_id per request
# ============================================================
SERVER_FILE="$ROOT/src/server.ts"
if [[ ! -f "$SERVER_FILE" ]]; then
  echo "⚠️ Could not find src/server.ts, skipping request DB context patch."
  exit 0
fi

echo "==> Patching src/server.ts to set Postgres session vars..."

# backup
cp -p "$SERVER_FILE" "$ROOT/scripts/.bak_server.ts.$STAMP"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("src/server.ts")
t = p.read_text(encoding="utf-8")

# We add a small hook after fastify is created AND after jwt plugin is registered.
# We'll insert an onRequest hook if not present.
if "set_config('app.user_id'" in t or "app.user_id" in t and "set_config" in t:
    print("✅ server.ts already appears patched for app.user_id/app.organization_id")
    raise SystemExit(0)

hook = r'''
// --- DB session context for RLS/audit triggers ---
fastify.addHook("preHandler", async (request) => {
  try {
    // If logged in, req.user is set by requireAuth on protected routes.
    const u = (request as any).user;
    const userId = u?.userId ?? u?.id ?? u?.sub ?? null;

    // Prefer x-organization-id header (your API already uses it)
    const orgId = String(request.headers["x-organization-id"] || "") || u?.organizationId || u?.org || null;

    if (userId) {
      await (fastify as any).pg.query("select set_config('app.user_id', $1, true)", [String(userId)]);
    } else {
      await (fastify as any).pg.query("select set_config('app.user_id', '', true)");
    }

    if (orgId) {
      await (fastify as any).pg.query("select set_config('app.organization_id', $1, true)", [String(orgId)]);
    } else {
      await (fastify as any).pg.query("select set_config('app.organization_id', '', true)");
    }
  } catch {
    // don't block requests if context setting fails
  }
});
'''

# Insert hook near end, before fastify.listen call.
# Try to locate "await fastify.listen" and insert above it.
m = re.search(r'\n\s*await\s+fastify\.listen\([^\n]+\);\s*\n', t)
if m:
    t = t[:m.start()] + "\n" + hook + "\n" + t[m.start():]
else:
    # fallback: append at end
    t += "\n" + hook + "\n"

p.write_text(t, encoding="utf-8")
print("✅ Patched src/server.ts (preHandler hook to set app.user_id/app.organization_id)")
PY

echo "✅ server.ts patched (backup at scripts/.bak_server.ts.$STAMP)"
echo
echo "==> Next: restart your server"
echo "   npm run dev"
