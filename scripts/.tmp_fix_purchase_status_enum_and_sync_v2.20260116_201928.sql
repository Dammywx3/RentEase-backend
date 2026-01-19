BEGIN;

-- Show current enum values
DO $$
DECLARE v text;
BEGIN
  RAISE NOTICE 'purchase_status enum values (before):';
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

-- Add 'paid' if missing
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
      -- fallback (older PG or if AFTER not supported)
      EXECUTE 'ALTER TYPE purchase_status ADD VALUE ''paid''';
      RAISE NOTICE 'Added purchase_status value: paid (appended)';
    END;
  ELSE
    RAISE NOTICE 'purchase_status already has value: paid';
  END IF;
END $$;

-- Sync status based on payment_status
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
