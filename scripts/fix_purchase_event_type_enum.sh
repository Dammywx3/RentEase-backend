#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DB_NAME="${DB_NAME:-rentease}"

STAMP="$(date +%Y%m%d_%H%M%S)"
BAK_DIR="$ROOT/scripts/.bak"
mkdir -p "$BAK_DIR"

SQL_FILE="$ROOT/scripts/.tmp_fix_purchase_event_type_enum.$STAMP.sql"

echo "==> DB_NAME=$DB_NAME"
echo "==> writing $SQL_FILE"

cat >"$SQL_FILE" <<'SQL'
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
SQL

echo "==> applying migration..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL_FILE"

echo "✅ purchase_event_type enum fixed"
