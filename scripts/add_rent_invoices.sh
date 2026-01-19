#!/usr/bin/env bash
set -euo pipefail

: "${DB_NAME:?DB_NAME env var is required}"
: "${ORG_ID:?ORG_ID env var is required (uuid)}"

echo "Using DB_NAME=$DB_NAME"
echo "Using ORG_ID=$ORG_ID"

psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<SQL
-- Create next rent invoices for ACTIVE tenancies only
-- Includes organization_id explicitly because psql sessions may not have RLS/org context set.

WITH active_t AS (
  SELECT
    t.id AS tenancy_id,
    t.tenant_id,
    t.property_id,
    t.next_due_date,
    t.rent_amount,
    t.payment_cycle
  FROM public.tenancies t
  WHERE t.deleted_at IS NULL
    AND t.status = 'active'::tenancy_status
),
periods AS (
  SELECT
    a.tenancy_id,
    a.tenant_id,
    a.property_id,
    a.next_due_date AS due_date,
    CASE a.payment_cycle
      WHEN 'monthly'   THEN (a.next_due_date - INTERVAL '1 month')::date
      WHEN 'quarterly' THEN (a.next_due_date - INTERVAL '3 months')::date
      WHEN 'yearly'    THEN (a.next_due_date - INTERVAL '1 year')::date
      WHEN 'biweekly'  THEN (a.next_due_date - INTERVAL '14 days')::date
      ELSE (a.next_due_date - INTERVAL '1 month')::date
    END AS period_start,
    (a.next_due_date - INTERVAL '1 day')::date AS period_end,
    a.rent_amount::numeric(15,2) AS subtotal
  FROM active_t a
),
ins AS (
  INSERT INTO public.rent_invoices (
    organization_id,
    tenancy_id,
    tenant_id,
    property_id,
    period_start,
    period_end,
    due_date,
    subtotal,
    late_fee_amount,
    total_amount,
    status,
    currency,
    paid_amount
  )
  SELECT
    '$ORG_ID'::uuid AS organization_id,
    p.tenancy_id,
    p.tenant_id,
    p.property_id,
    p.period_start,
    p.period_end,
    p.due_date,
    p.subtotal,
    0::numeric(15,2) AS late_fee_amount,
    p.subtotal       AS total_amount,
    'issued'::invoice_status,
    'USD',
    0::numeric(15,2) AS paid_amount
  FROM periods p
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.rent_invoices ri
    WHERE ri.deleted_at IS NULL
      AND ri.organization_id = '$ORG_ID'::uuid
      AND ri.tenancy_id = p.tenancy_id
      AND ri.period_start = p.period_start
      AND ri.period_end = p.period_end
      AND ri.due_date = p.due_date
  )
  RETURNING id, tenancy_id, due_date, period_start, period_end, total_amount, status
)
SELECT
  count(*) AS inserted_count
FROM ins;
SQL

echo "✅ Done."
