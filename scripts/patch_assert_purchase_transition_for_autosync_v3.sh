#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DB_NAME="${DB_NAME:-rentease}"
TS="$(date +%Y%m%d_%H%M%S)"
SQL_FILE="scripts/.tmp_patch_assert_purchase_transition_v3.${TS}.sql"

echo "==> ROOT=$ROOT"
echo "==> DB_NAME=$DB_NAME"
echo "==> Writing $SQL_FILE"

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- 1) Helper: rank purchase_status progression (standalone function)
CREATE OR REPLACE FUNCTION public.purchase_status_rank(s text)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE s
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
$$;

-- 2) Drop old transition guard (avoid "cannot change name of input parameter" issues)
DROP FUNCTION IF EXISTS public.assert_purchase_transition(text,text,text,text);

-- 3) Recreate transition guard with AUTO-SYNC allowances
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
  o_pay text;
  n_pay text;
  o_stat text;
  n_stat text;
BEGIN
  o_pay  := COALESCE(old_pay, '');
  n_pay  := COALESCE(new_pay, '');
  o_stat := COALESCE(old_status, '');
  n_stat := COALESCE(new_status, '');

  -- -----------------------------
  -- A) PAYMENT STATUS transitions
  -- -----------------------------
  IF old_pay IS DISTINCT FROM new_pay THEN
    -- Allowed:
    -- unpaid/'' -> paid
    -- paid -> refunded
    -- (same -> same)
    IF NOT (
      (o_pay IN ('', 'unpaid') AND n_pay = 'paid') OR
      (o_pay = 'paid' AND n_pay = 'refunded') OR
      (o_pay = n_pay)
    ) THEN
      RAISE EXCEPTION 'Illegal payment_status transition: % -> %', o_pay, n_pay
        USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- -----------------------------
  -- B) BUSINESS STATUS transitions
  -- -----------------------------
  IF old_status IS DISTINCT FROM new_status THEN

    -- Terminal states: can't move away
    IF o_stat IN ('closed','cancelled','refunded') AND n_stat <> o_stat THEN
      RAISE EXCEPTION 'Cannot transition out of terminal status: % -> %', o_stat, n_stat
        USING ERRCODE = 'P0001';
    END IF;

    -- AUTO-SYNC allowances (status follows payment_status)
    IF (n_pay = 'paid' AND n_stat = 'paid') THEN
      RETURN;
    END IF;

    IF (n_pay = 'refunded' AND n_stat = 'refunded') THEN
      RETURN;
    END IF;

    -- Allow cancellation from most non-terminal states
    IF n_stat = 'cancelled' THEN
      RETURN;
    END IF;

    -- Normal forward-only progression using rank
    old_rank := public.purchase_status_rank(o_stat);
    new_rank := public.purchase_status_rank(n_stat);

    IF old_rank = 0 OR new_rank = 0 THEN
      RAISE EXCEPTION 'Unknown purchase_status in transition: % -> %', o_stat, n_stat
        USING ERRCODE = 'P0001';
    END IF;

    IF new_rank < old_rank THEN
      RAISE EXCEPTION 'Backward status transition not allowed: % -> %', o_stat, n_stat
        USING ERRCODE = 'P0001';
    END IF;

    RETURN;
  END IF;

END;
$$;

COMMIT;

-- quick sanity output
SELECT
  'ok' as result,
  public.purchase_status_rank('under_contract') as under_contract_rank,
  public.purchase_status_rank('paid') as paid_rank;

SQL

echo "==> Applying $SQL_FILE to DB_NAME=$DB_NAME ..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
echo "✅ Patched public.assert_purchase_transition + added purchase_status_rank() successfully."
