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
