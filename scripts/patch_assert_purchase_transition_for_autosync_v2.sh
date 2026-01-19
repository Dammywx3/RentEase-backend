#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DB_NAME="${DB_NAME:-rentease}"
TS="$(date +%Y%m%d_%H%M%S)"
SQL_FILE="scripts/.tmp_patch_assert_purchase_transition_v2.${TS}.sql"

echo "==> ROOT=$ROOT"
echo "==> DB_NAME=$DB_NAME"
echo "==> Writing $SQL_FILE"

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- IMPORTANT:
-- Postgres can error on CREATE OR REPLACE if the existing function has different parameter NAMES.
-- So we DROP by signature, then CREATE fresh.
DROP FUNCTION IF EXISTS public.assert_purchase_transition(text,text,text,text);

CREATE FUNCTION public.assert_purchase_transition(
  old_status text,
  new_status text,
  old_pay text,
  new_pay text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  old_rank int;
  new_rank int;

  -- helper order for normal forward business flow
  FUNCTION status_rank(s text) RETURNS int
  LANGUAGE plpgsql
  AS $f$
  BEGIN
    RETURN CASE s
      WHEN 'initiated'         THEN 10
      WHEN 'offer_made'        THEN 20
      WHEN 'offer_accepted'    THEN 30
      WHEN 'under_contract'    THEN 40
      WHEN 'paid'              THEN 50
      WHEN 'escrow_opened'     THEN 60
      WHEN 'deposit_paid'      THEN 70
      WHEN 'inspection'        THEN 80
      WHEN 'financing'         THEN 90
      WHEN 'appraisal'         THEN 100
      WHEN 'title_search'      THEN 110
      WHEN 'closing_scheduled' THEN 120
      WHEN 'closed'            THEN 130
      WHEN 'cancelled'         THEN 900
      WHEN 'refunded'          THEN 950
      ELSE 0
    END;
  END;
  $f$;

BEGIN
  -- -----------------------------
  -- A) PAYMENT STATUS transitions
  -- -----------------------------
  IF old_pay IS DISTINCT FROM new_pay THEN
    old_pay := COALESCE(old_pay, '');
    new_pay := COALESCE(new_pay, '');

    -- Allowed:
    -- unpaid -> paid
    -- paid -> refunded
    IF NOT (
      (old_pay IN ('', 'unpaid') AND new_pay = 'paid') OR
      (old_pay = 'paid' AND new_pay = 'refunded') OR
      (old_pay = new_pay)
    ) THEN
      RAISE EXCEPTION 'Illegal payment_status transition: % -> %', old_pay, new_pay
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- -----------------------------
  -- B) BUSINESS STATUS transitions
  -- -----------------------------
  IF old_status IS DISTINCT FROM new_status THEN
    old_status := COALESCE(old_status, '');
    new_status := COALESCE(new_status, '');

    -- Terminal states: block changing away from them
    IF old_status IN ('closed','cancelled','refunded') AND new_status <> old_status THEN
      RAISE EXCEPTION 'Cannot transition out of terminal status: % -> %', old_status, new_status
        USING ERRCODE = 'P0001';
    END IF;

    -- AUTO-SYNC allowances
    IF (new_pay = 'paid' AND new_status = 'paid') THEN
      RETURN;
    END IF;

    IF (new_pay = 'refunded' AND new_status = 'refunded') THEN
      RETURN;
    END IF;

    -- Allow cancellation from most non-terminal states
    IF new_status = 'cancelled' THEN
      RETURN;
    END IF;

    -- Normal forward-only progression by rank
    old_rank := status_rank(old_status);
    new_rank := status_rank(new_status);

    IF old_rank = 0 OR new_rank = 0 THEN
      RAISE EXCEPTION 'Unknown purchase_status in transition: % -> %', old_status, new_status
        USING ERRCODE = 'P0001';
    END IF;

    IF old_rank = new_rank THEN
      RETURN;
    END IF;

    IF new_rank < old_rank THEN
      RAISE EXCEPTION 'Backward status transition not allowed: % -> %', old_status, new_status
        USING ERRCODE = 'P0001';
    END IF;

    RETURN;
  END IF;

END;
$$;

COMMIT;

-- Show function signature installed
SELECT 'assert_purchase_transition installed' as ok;

SQL

echo "==> Applying $SQL_FILE to DB_NAME=$DB_NAME ..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
echo "✅ Patched public.assert_purchase_transition (drop + recreate) successfully."
