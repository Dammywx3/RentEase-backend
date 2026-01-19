#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"
SQL_FILE="sql/2026_01_18_purchase_close_complete_FIXED.sql"
mkdir -p sql

echo "==> Writing robust migration: $SQL_FILE"

cat > "$SQL_FILE" <<'SQL'
BEGIN;

-- ============================================================
-- 0) Ensure audit_logs exists (ONLY if missing)
--    If it exists, we will NOT recreate it.
-- ============================================================
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT public.rentease_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 1) Helper: safe insert audit log regardless of table columns
-- ============================================================
CREATE OR REPLACE FUNCTION public.safe_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_org_id uuid DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  cols text[] := ARRAY[]::text[];
  vals text[] := ARRAY[]::text[];
  sql text;
BEGIN
  -- Only insert into columns that exist
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='action') THEN
    cols := cols || 'action'; vals := vals || '$1';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_type') THEN
    cols := cols || 'entity_type'; vals := vals || '$2';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name IN ('entity_id','reference_id')) THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_id') THEN
      cols := cols || 'entity_id'; vals := vals || '$3';
    ELSE
      cols := cols || 'reference_id'; vals := vals || '$3';
    END IF;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='payload') THEN
    cols := cols || 'payload'; vals := vals || '$4';
  END IF;

  IF p_org_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='organization_id') THEN
    cols := cols || 'organization_id'; vals := vals || '$5';
  END IF;

  IF p_actor_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name IN ('actor_id','user_id','created_by')) THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='actor_id') THEN
      cols := cols || 'actor_id'; vals := vals || '$6';
    ELSIF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='created_by') THEN
      cols := cols || 'created_by'; vals := vals || '$6';
    ELSE
      cols := cols || 'user_id'; vals := vals || '$6';
    END IF;
  END IF;

  -- If none of the expected columns exist, just insert a bare row (id + created_at default)
  IF array_length(cols, 1) IS NULL THEN
    INSERT INTO public.audit_logs DEFAULT VALUES;
    RETURN;
  END IF;

  sql := format(
    'INSERT INTO public.audit_logs (%s) VALUES (%s)',
    array_to_string(cols, ', '),
    array_to_string(vals, ', ')
  );

  EXECUTE sql USING p_action, p_entity_type, p_entity_id, p_payload, p_org_id, p_actor_id;
END;
$$;

-- ============================================================
-- 2) Close purchase (status + timestamps) + write audit log
-- ============================================================
CREATE OR REPLACE FUNCTION public.purchase_close_complete(
  p_purchase_id uuid,
  p_org_id uuid DEFAULT NULL,
  p_actor_id uuid DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_exists boolean;
  v_status_col_type text;
  v_status_udt text;
  v_target_status text := 'closed';
  v_payload jsonb;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM public.property_purchases
    WHERE id = p_purchase_id
      AND deleted_at IS NULL
      AND (p_org_id IS NULL OR organization_id = p_org_id)
  ) INTO v_exists;

  IF NOT v_exists THEN
    RETURN jsonb_build_object('ok', false, 'error', 'PURCHASE_NOT_FOUND');
  END IF;

  -- Determine status type
  SELECT c.data_type, c.udt_name
  INTO v_status_col_type, v_status_udt
  FROM information_schema.columns c
  WHERE c.table_schema='public' AND c.table_name='property_purchases' AND c.column_name='status'
  LIMIT 1;

  -- If status is an enum, pick a valid label if 'closed' isn't present
  IF v_status_col_type = 'USER-DEFINED' THEN
    IF NOT EXISTS (
      SELECT 1
      FROM pg_type t
      JOIN pg_enum e ON e.enumtypid = t.oid
      JOIN pg_namespace n ON n.oid = t.typnamespace
      WHERE n.nspname='public'
        AND t.typname = v_status_udt
        AND e.enumlabel = 'closed'
    ) THEN
      -- fallbacks
      IF EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_enum e ON e.enumtypid = t.oid
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname='public'
          AND t.typname = v_status_udt
          AND e.enumlabel = 'completed'
      ) THEN
        v_target_status := 'completed';
      ELSIF EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_enum e ON e.enumtypid = t.oid
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname='public'
          AND t.typname = v_status_udt
          AND e.enumlabel = 'successful'
      ) THEN
        v_target_status := 'successful';
      ELSE
        -- last resort: keep as-is (do not update status)
        v_target_status := '';
      END IF;
    END IF;
  END IF;

  -- Update timestamps + status if safe
  IF v_target_status <> '' THEN
    EXECUTE format(
      'UPDATE public.property_purchases
       SET status = %L%s,
           closed_at = COALESCE(closed_at, now()),
           updated_at = now()
       WHERE id = $1
         AND deleted_at IS NULL
         AND ($2::uuid IS NULL OR organization_id = $2::uuid)',
      v_target_status,
      CASE WHEN v_status_col_type='USER-DEFINED' THEN '::public.'||quote_ident(v_status_udt) ELSE '' END
    )
    USING p_purchase_id, p_org_id;
  ELSE
    UPDATE public.property_purchases
    SET closed_at = COALESCE(closed_at, now()),
        updated_at = now()
    WHERE id = p_purchase_id
      AND deleted_at IS NULL
      AND (p_org_id IS NULL OR organization_id = p_org_id);
  END IF;

  v_payload := jsonb_build_object(
    'purchase_id', p_purchase_id,
    'status_set', v_target_status,
    'note', COALESCE(p_note,'')
  );

  PERFORM public.safe_audit_log(
    'purchase_close_complete',
    'purchase',
    p_purchase_id,
    v_payload,
    p_org_id,
    p_actor_id
  );

  RETURN jsonb_build_object('ok', true, 'purchase_id', p_purchase_id, 'status_set', v_target_status);
END;
$$;

COMMIT;
SQL

echo "==> Applying migration..."
psql -X -P pager=off -d "$DB" -v ON_ERROR_STOP=1 -f "$SQL_FILE"

echo
echo "✅ Migration applied: $SQL_FILE"
echo
echo "==> Sanity checks:"
psql -X -P pager=off -d "$DB" -c "\df+ public.purchase_close_complete" || true
psql -X -P pager=off -d "$DB" -c "\df+ public.safe_audit_log" || true

echo
echo "✅ Done."
