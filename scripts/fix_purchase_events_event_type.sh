#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-rentease}"
STAMP="$(date +%Y%m%d_%H%M%S)"
SQL_FILE="scripts/.tmp_fix_purchase_events_event_type.$STAMP.sql"

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- 1) Create a dedicated enum for money / audit events
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname='purchase_audit_event_type') THEN
    CREATE TYPE purchase_audit_event_type AS ENUM (
      'created',
      'status_changed',
      'paid',
      'completed',
      'refunded'
    );
  END IF;
END $$;

-- 2) If purchase_events.event_type currently uses purchase_event_type (pipeline enum),
--    migrate it to purchase_audit_event_type safely.
DO $$
DECLARE
  cur_type text;
BEGIN
  SELECT atttypid::regtype::text
  INTO cur_type
  FROM pg_attribute
  WHERE attrelid = 'public.purchase_events'::regclass
    AND attname = 'event_type'
    AND attnum > 0
    AND NOT attisdropped;

  -- Only migrate if it's NOT already using purchase_audit_event_type
  IF cur_type <> 'purchase_audit_event_type' THEN
    ALTER TABLE public.purchase_events
      ALTER COLUMN event_type TYPE text;

    -- normalize existing values into the new enum set
    -- (keep any unknown values as 'status_changed' with metadata note later)
    ALTER TABLE public.purchase_events
      ALTER COLUMN event_type TYPE purchase_audit_event_type
      USING (
        CASE
          WHEN event_type IN ('created','status_changed','paid','completed','refunded')
            THEN event_type::purchase_audit_event_type
          ELSE 'status_changed'::purchase_audit_event_type
        END
      );
  END IF;
END $$;

COMMIT;

-- verify
SELECT atttypid::regtype::text AS event_type_column_type
FROM pg_attribute
WHERE attrelid = 'public.purchase_events'::regclass
  AND attname = 'event_type'
  AND attnum > 0
  AND NOT attisdropped;
SQL

echo "==> applying $SQL_FILE to DB_NAME=$DB_NAME"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"
echo "✅ purchase_events.event_type now uses purchase_audit_event_type"
