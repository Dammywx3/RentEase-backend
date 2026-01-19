BEGIN;

-- Ensure enum exists
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'purchase_event_type') THEN
    CREATE TYPE purchase_event_type AS ENUM ('created');
  END IF;
END $$;

-- Add missing enum values (idempotent)
DO $$
DECLARE
  v text;
  vals text[] := ARRAY['created','status_changed','paid','completed','refunded'];
BEGIN
  FOREACH v IN ARRAY vals LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_enum e
      JOIN pg_type t ON t.oid = e.enumtypid
      WHERE t.typname = 'purchase_event_type'
        AND e.enumlabel = v
    ) THEN
      EXECUTE format('ALTER TYPE purchase_event_type ADD VALUE %L', v);
    END IF;
  END LOOP;
END $$;

COMMIT;

-- Show current enum values
SELECT e.enumlabel
FROM pg_enum e
JOIN pg_type t ON t.oid = e.enumtypid
WHERE t.typname='purchase_event_type'
ORDER BY e.enumsortorder;
