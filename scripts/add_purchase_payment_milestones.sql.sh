#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-rentease}"

PAGER=cat psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

-- 1) Payment milestone enum (separate from purchase_status)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_payment_status') THEN
    CREATE TYPE purchase_payment_status AS ENUM ('unpaid','deposit_paid','partially_paid','paid','refunded');
  END IF;
END $$;

-- 2) Add milestone columns (safe)
ALTER TABLE public.property_purchases
  ADD COLUMN IF NOT EXISTS payment_status purchase_payment_status NOT NULL DEFAULT 'unpaid'::purchase_payment_status,
  ADD COLUMN IF NOT EXISTS paid_at timestamptz,
  ADD COLUMN IF NOT EXISTS paid_amount numeric(15,2),
  ADD COLUMN IF NOT EXISTS last_payment_id uuid;

-- 3) Add constraints safely (Postgres has no "ADD CONSTRAINT IF NOT EXISTS")
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_purchase_paid_amount_nonneg'
  ) THEN
    ALTER TABLE public.property_purchases
      ADD CONSTRAINT chk_purchase_paid_amount_nonneg
      CHECK (paid_amount IS NULL OR paid_amount >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_purchase_paid_amount_not_more_than_agreed'
  ) THEN
    ALTER TABLE public.property_purchases
      ADD CONSTRAINT chk_purchase_paid_amount_not_more_than_agreed
      CHECK (paid_amount IS NULL OR paid_amount <= agreed_price);
  END IF;
END $$;

-- 4) Index safely
CREATE INDEX IF NOT EXISTS idx_property_purchases_payment_status
  ON public.property_purchases(payment_status, created_at DESC);

COMMIT;
SQL

echo "✅ Added purchase payment milestone fields to public.property_purchases"
