BEGIN;

-- Add refund audit fields to purchases (safe if already exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refund_method'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refund_method text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refunded_reason'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refunded_reason text;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refunded_by'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refunded_by uuid;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='property_purchases' AND column_name='refund_payment_id'
  ) THEN
    ALTER TABLE public.property_purchases ADD COLUMN refund_payment_id uuid;
  END IF;
END $$;

-- Indexes (only if missing)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_property_purchases_refunded_by'
  ) THEN
    CREATE INDEX idx_property_purchases_refunded_by
      ON public.property_purchases(refunded_by, refunded_at DESC)
      WHERE refunded_by IS NOT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_property_purchases_refund_payment_id'
  ) THEN
    CREATE INDEX idx_property_purchases_refund_payment_id
      ON public.property_purchases(refund_payment_id)
      WHERE refund_payment_id IS NOT NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public' AND indexname='idx_property_purchases_refund_method'
  ) THEN
    CREATE INDEX idx_property_purchases_refund_method
      ON public.property_purchases(refund_method, refunded_at DESC)
      WHERE refund_method IS NOT NULL;
  END IF;
END $$;

-- Foreign keys (safe add-if-missing via pg_constraint checks)
DO $$
BEGIN
  -- refunded_by -> users.id
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='property_purchases_refunded_by_fkey'
  ) THEN
    ALTER TABLE public.property_purchases
      ADD CONSTRAINT property_purchases_refunded_by_fkey
      FOREIGN KEY (refunded_by) REFERENCES public.users(id)
      ON DELETE SET NULL;
  END IF;

  -- refund_payment_id -> payments.id
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname='property_purchases_refund_payment_id_fkey'
  ) THEN
    ALTER TABLE public.property_purchases
      ADD CONSTRAINT property_purchases_refund_payment_id_fkey
      FOREIGN KEY (refund_payment_id) REFERENCES public.payments(id)
      ON DELETE SET NULL;
  END IF;
END $$;

COMMIT;
