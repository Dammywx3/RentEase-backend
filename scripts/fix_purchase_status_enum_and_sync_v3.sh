#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DB_NAME="${DB_NAME:-rentease}"
STAMP="$(date +%Y%m%d_%H%M%S)"
SQL1="scripts/.tmp_fix_purchase_status_enum_only.$STAMP.sql"
SQL2="scripts/.tmp_fix_purchase_status_sync_only.$STAMP.sql"

echo "==> DB_NAME=$DB_NAME"
echo "==> Writing $SQL1"
cat > "$SQL1" <<'SQL'
-- 1) Add enum value 'paid' if missing (must commit before use)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname='purchase_status' AND e.enumlabel='paid'
  ) THEN
    BEGIN
      EXECUTE 'ALTER TYPE purchase_status ADD VALUE ''paid'' AFTER ''under_contract''';
      RAISE NOTICE 'Added purchase_status value: paid (AFTER under_contract)';
    EXCEPTION WHEN others THEN
      EXECUTE 'ALTER TYPE purchase_status ADD VALUE ''paid''';
      RAISE NOTICE 'Added purchase_status value: paid (appended)';
    END;
  ELSE
    RAISE NOTICE 'purchase_status already has value: paid';
  END IF;
END $$;

-- show values after
DO $$
DECLARE v text;
BEGIN
  RAISE NOTICE 'purchase_status enum values (after):';
  FOR v IN
    SELECT e.enumlabel
    FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname='purchase_status'
    ORDER BY e.enumsortorder
  LOOP
    RAISE NOTICE ' - %', v;
  END LOOP;
END $$;
SQL

echo "==> Applying enum patch (must be its own transaction)..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL1"
echo "✅ Enum patch applied"

echo "==> Writing $SQL2"
cat > "$SQL2" <<'SQL'
BEGIN;

-- 2) Sync status based on payment_status (now safe to use 'paid')
UPDATE public.property_purchases
SET status = 'paid',
    updated_at = now()
WHERE deleted_at IS NULL
  AND payment_status::text = 'paid'
  AND status::text = 'under_contract';

COMMIT;

-- Report
SELECT
  status::text as status,
  payment_status::text as payment_status,
  count(*) as cnt
FROM public.property_purchases
WHERE deleted_at IS NULL
GROUP BY 1,2
ORDER BY 3 DESC;
SQL

echo "==> Applying sync update..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL2"
echo "✅ Done: status sync applied."
