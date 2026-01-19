#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-rentease}"
WITH_RLS="${WITH_RLS:-0}"

# Pick the newest temp SQL you already generated
SQL_FILE="$(ls -1t scripts/.tmp_fix_purchase_actor_context.*.sql 2>/dev/null | head -n 1)"

if [[ -z "${SQL_FILE:-}" ]]; then
  echo "❌ No scripts/.tmp_fix_purchase_actor_context.*.sql found"
  exit 1
fi

echo "==> DB_NAME=$DB_NAME"
echo "==> Using SQL_FILE=$SQL_FILE"
echo "==> Applying actor-context patch..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"

if [[ "$WITH_RLS" == "1" ]]; then
  echo "==> EnQLS=1: enabling RLS for purchases + purchase_events (BASIC org isolation)..."
  psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

ALTER TABLE public.property_purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_events ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='property_purchases' AND policyname='purchases_org_isolation'
  ) THEN
    CREATE POLICY purchases_org_isolation
    ON public.property_purchases
    USING (organization_id = public.current_organization_uuid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='purchase_events' AND policyname='purchase_events_org_isolation'
  ) THEN
    CREATE POLICY purchase_events_org_isolation
    ON public.purchase_events
    USING (organization_id = public.current_organization_uuid());
  END IF;
END $$;

COMMIT;
SQL
fi

echo "✅ done"
