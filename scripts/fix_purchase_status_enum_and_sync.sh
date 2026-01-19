#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DB_NAME="${DB_NAME:-rentease}"
SQL_FILE="scripts/.tmp_fix_purchase_status_enum_and_sync.$(date +%Y%m%d_%H%M%S).sql"

echo "==> DB_NAME=$DB_NAME"
echo "==> Writing $SQL_FILE"

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- 1) Show current purchase_status enum values (debug)
DO $$
DECLARE
  v text;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname='purchase_status') THEN
    RAISE NOTICE 'purchase_status enum values:';
    FOR v IN
      SELECT e.enumlabel
      FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      WHERE t.typname='purchase_status'
      ORDER BY e.enumsortorder
    LOOP
      RAISE NOTICE ' - %', v;
    END LOOP;
  ELSE
    RAISE EXCEPTION 'Enum type purchase_status does not exist';
  END IF;
END $$;

-- 2) Add 'paid' to purchase_status if missing
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname='purchase_status'
      AND e.enumlabel='paid'
  ) THEN

    -- Prefer inserting after under_contract if that label exists (clean ordering)
    IF EXISTS (
      SELECT 1
      FROM pg_enum e
      JOIN pg_type t ON t.oid=e.enumtypid
      WHERE t.typname='purchase_status'
        AND e.enumlabel='under_contract'
    ) THEN
      EXECUTE $$ALTER TYPE purchase_status ADD VALUE 'paid' AFTER 'under_contract'$$;
    ELSE
      EXECUTE $$ALTER TYPE purchase_status ADD VALUE 'paid'$$;
    END IF;

    RAISE NOTICE 'Added purchase_status value: paid';
  ELSE
    RAISE NOTICE 'purchase_status already has value: paid';
  END IF;
END $$;

-- 3) Status sync repair
-- Only sync cases you intended: under_contract + payment_status=paid => status=paid
UPDATE public.property_purchases
SET status = 'paid',
    updated_at = now()
WHERE deleted_at IS NULL
  AND payment_status::text = 'paid'
  AND status::text = 'under_contract';

COMMIT;

-- 4) Quick report
SELECT
  status::text as status,
  payment_status::text as payment_status,
  count(*) as cnt
FROM public.property_purchases
WHERE deleted_at IS NULL
GROUP BY 1,2
ORDER BY 3 DESC;
SQL

echo "==> Applying $SQL_FILE ..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
echo "✅ Done: purchase_status now supports 'paid' and status sync applied."
