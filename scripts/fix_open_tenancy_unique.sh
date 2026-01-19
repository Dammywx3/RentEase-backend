#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-rentease}"

echo "✅ Step 0: show current duplicates (open tenancies: active + pending_start)"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
WITH d AS (
  SELECT tenant_id, property_id, COUNT(*) AS n
  FROM public.tenancies
  WHERE deleted_at IS NULL AND status IN ('active','pending_start')
  GROUP BY tenant_id, property_id
  HAVING COUNT(*) > 1
)
SELECT * FROM d ORDER BY n DESC;
"

echo
echo "✅ Step 1: soft-delete duplicates (keep newest by created_at)"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
WITH ranked AS (
  SELECT
    id,
    tenant_id,
    property_id,
    created_at,
    ROW_NUMBER() OVER (
      PARTITION BY tenant_id, property_id
      ORDER BY created_at DESC, id DESC
    ) AS rn
  FROM public.tenancies
  WHERE deleted_at IS NULL AND status IN ('active','pending_start')
)
UPDATE public.tenancies t
SET deleted_at = NOW()
FROM ranked r
WHERE t.id = r.id AND r.rn > 1;
"

echo
echo "✅ Step 2: create the correct UNIQUE index for open tenancy (active + pending_start)"
echo "   (must be CONCURRENTLY, so NOT inside BEGIN/COMMIT)"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uniq_open_tenancy
ON public.tenancies (tenant_id, property_id)
WHERE deleted_at IS NULL AND status IN ('active','pending_start');
"

echo
echo "✅ Step 3 (optional): drop old active-only index if it exists"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
DROP INDEX CONCURRENTLY IF EXISTS uniq_active_tenancy;
"

echo
echo "✅ Step 4: confirm duplicates are gone"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -c "
WITH d AS (
  SELECT tenant_id, property_id, COUNT(*) AS n
  FROM public.tenancies
  WHERE deleted_at IS NULL AND status IN ('active','pending_start')
  GROUP BY tenant_id, property_id
  HAVING COUNT(*) > 1
)
SELECT * FROM d ORDER BY n DESC;
"

echo
echo "✅ Done. Open-tenancy duplicates fixed + DB guardrail added."
