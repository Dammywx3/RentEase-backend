-- 1) Show duplicates (open tenancies) BEFORE cleanup
WITH d AS (
  SELECT tenant_id, property_id, COUNT(*) AS n
  FROM public.tenancies
  WHERE deleted_at IS NULL AND status IN ('active','pending_start')
  GROUP BY tenant_id, property_id
  HAVING COUNT(*) > 1
)
SELECT * FROM d ORDER BY n DESC;

-- 2) Soft-delete duplicates (keep newest by created_at)
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

-- 3) Create unique index for OPEN tenancies (ACTIVE + PENDING_START)
-- NOTE: must be CONCURRENTLY, and cannot run inside BEGIN/COMMIT.
CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uniq_open_tenancy
ON public.tenancies (tenant_id, property_id)
WHERE deleted_at IS NULL AND status IN ('active','pending_start');

-- 4) (Optional) Drop the old "active only" unique index (your schema shows uniq_active_tenancy)
DROP INDEX CONCURRENTLY IF EXISTS uniq_active_tenancy;

-- 5) Confirm no duplicates remain
WITH d AS (
  SELECT tenant_id, property_id, COUNT(*) AS n
  FROM public.tenancies
  WHERE deleted_at IS NULL AND status IN ('active','pending_start')
  GROUP BY tenant_id, property_id
  HAVING COUNT(*) > 1
)
SELECT * FROM d ORDER BY n DESC;
