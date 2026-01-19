BEGIN;

-- 1) Add refund milestone fields to purchases (safe if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refunded_at'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refunded_at timestamptz;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refunded_amount'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refunded_amount numeric(15,2);
  END IF;
END $$;

-- Constraints / indexes (Postgres doesn't support "ADD CONSTRAINT IF NOT EXISTS", so we do DO-block checks)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'chk_purchase_refunded_amount_nonneg'
  ) THEN
    ALTER TABLE public.property_purchases
      ADD CONSTRAINT chk_purchase_refunded_amount_nonneg
      CHECK (refunded_amount IS NULL OR refunded_amount >= 0::numeric);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_property_purchases_refunded_at'
  ) THEN
    CREATE INDEX idx_property_purchases_refunded_at
      ON public.property_purchases(refunded_at DESC)
      WHERE refunded_at IS NOT NULL;
  END IF;
END $$;

-- 2) Ensure wallet_transaction_type enum has debit types for refunds.
-- We add values only if missing.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname='wallet_transaction_type') THEN

    IF NOT EXISTS (
      SELECT 1
      FROM pg_enum e
      JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname='wallet_transaction_type' AND e.enumlabel='debit_payee'
    ) THEN
      EXECUTE 'ALTER TYPE wallet_transaction_type ADD VALUE ''debit_payee''';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM pg_enum e
      JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname='wallet_transaction_type' AND e.enumlabel='debit_platform_fee'
    ) THEN
      EXECUTE 'ALTER TYPE wallet_transaction_type ADD VALUE ''debit_platform_fee''';
    END IF;

  END IF;
END $$;

COMMIT;
