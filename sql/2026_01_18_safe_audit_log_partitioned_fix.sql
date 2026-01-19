BEGIN;

-- This replaces public.safe_audit_log so it works with BOTH schemas:
-- A) "old style" columns: action/entity_type/entity_id/payload/organization_id/actor_id
-- B) your current schema: table_name, record_id, operation (enum), changed_by, change_details
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

  op_enum_schema text;
  op_enum_name text;
  chosen_op text;
BEGIN
  -- ------------------------------------------------------------
  -- Case B: partitioned audit_logs (table_name + operation required)
  -- ------------------------------------------------------------
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='audit_logs' AND column_name='table_name'
  )
  AND EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='audit_logs' AND column_name='operation'
  )
  THEN
    -- Choose an operation label from enum public.audit_operation (or whatever schema owns it)
    SELECT c.udt_schema, c.udt_name
    INTO op_enum_schema, op_enum_name
    FROM information_schema.columns c
    WHERE c.table_schema='public' AND c.table_name='audit_logs' AND c.column_name='operation'
    LIMIT 1;

    -- Prefer UPDATE-like, else fallback to first enum label
    EXECUTE format(
      $q$
      WITH labels AS (
        SELECT e.enumlabel AS label
        FROM pg_type t
        JOIN pg_enum e ON e.enumtypid=t.oid
        JOIN pg_namespace n ON n.oid=t.typnamespace
        WHERE n.nspname=%L AND t.typname=%L
        ORDER BY e.enumsortorder
      )
      SELECT
        COALESCE(
          (SELECT label FROM labels WHERE lower(label) IN ('update','updated','modify','modified','change','changed') LIMIT 1),
          (SELECT label FROM labels LIMIT 1)
        )
      $q$,
      op_enum_schema, op_enum_name
    )
    INTO chosen_op;

    IF chosen_op IS NULL OR chosen_op = '' THEN
      RAISE EXCEPTION 'Could not resolve an audit_operation enum label.';
    END IF;

    -- Build insert dynamically with only columns that exist
    cols := cols || 'table_name';      vals := vals || '$1';
    cols := cols || 'operation';       vals := vals || format('$2::%I.%I', op_enum_schema, op_enum_name);

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='record_id') THEN
      cols := cols || 'record_id';     vals := vals || '$3';
    END IF;

    IF p_actor_id IS NOT NULL AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='changed_by') THEN
      cols := cols || 'changed_by';    vals := vals || '$4';
    END IF;

    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='change_details') THEN
      cols := cols || 'change_details'; vals := vals || '$5';
    END IF;

    sql := format(
      'INSERT INTO public.audit_logs (%s) VALUES (%s)',
      array_to_string(cols, ', '),
      array_to_string(vals, ', ')
    );

    EXECUTE sql
      USING
        COALESCE(NULLIF(trim(p_entity_type),''), 'unknown'), -- table_name
        chosen_op,                                          -- operation enum text
        p_entity_id,                                        -- record_id
        p_actor_id,                                         -- changed_by
        COALESCE(p_payload,'{}'::jsonb);                     -- change_details

    RETURN;
  END IF;

  -- ------------------------------------------------------------
  -- Case A: "old style" audit_logs columns (if present)
  -- ------------------------------------------------------------
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='action') THEN
    cols := cols || 'action'; vals := vals || '$1';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_type') THEN
    cols := cols || 'entity_type'; vals := vals || '$2';
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_id') THEN
    cols := cols || 'entity_id'; vals := vals || '$3';
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

  IF array_length(cols, 1) IS NULL THEN
    -- If neither schema fits, do nothing (avoid NOT NULL explosions)
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

COMMIT;
