#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DB_NAME="${DB_NAME:-rentease}"
STAMP="$(date +%Y%m%d_%H%M%S)"
SQL="scripts/.tmp_fix_purchase_status_sync_refunded_and_paid.$STAMP.sql"

echo "==> DB_NAME=$DB_NAME"
echo "==> Writing $SQL"

cat > "$SQL" <<'SQL'
BEGIN;

-- 1) If money got refunded, status must be refunded (per your desired flow)
UPDATE public.property_purchases
SET status = 'refunded',
    updated_at = now()
WHERE deleted_at IS NULL
  AND payment_status::text = 'refunded'
  AND status::text <> 'refunded';

-- 2) If money got paid and you want status reflect it, set status=paid
UPDATE public.property_purchases
SET status = 'paid',
    updated_at = now()
WHERE deleted_at IS NULL
  AND payment_status::text = 'paid'
  AND status::text = 'under_contract';

COMMIT;

-- Report after
SELECT status::text as status, payment_status::text as payment_status, count(*) as cnt
FROM public.property_purchases
WHERE deleted_at IS NULL
GROUP BY 1,2
ORDER BY 3 DESC;
SQL

echo "==> Applying..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL"
echo "✅ Done"
