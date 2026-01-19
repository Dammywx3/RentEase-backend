BEGIN;

CREATE OR REPLACE FUNCTION public.safe_audit_log(
  p_action text,
  p_entity_type text,
  p_entity_id uuid,
  p_payload jsonb DEFAULT '{}'::jsonb,
  p_org_id uuid DEFAULT NULL::uuid,
  p_actor_id uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  op_enum_schema text;
  op_enum_name   text;
  chosen_op      text;
BEGIN
  -- Only handle the "partitioned audit_logs" schema you actually have
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='audit_logs' AND column_name='operation'
  ) THEN
    RETURN;
  END IF;

  -- Find the enum type behind audit_logs.operation (schema+name)
  SELECT c.udt_schema, c.udt_name
  INTO op_enum_schema, op_enum_name
  FROM information_schema.columns c
  WHERE c.table_schema='public' AND c.table_name='audit_logs' AND c.column_name='operation'
  LIMIT 1;

  -- Choose a valid enum label:
  -- 1) If p_action matches a label, use it
  -- 2) else prefer an "update-like" label if present
  -- 3) else fallback to the FIRST enum label
  EXECUTE format($q$
    WITH labels AS (
      SELECT e.enumlabel AS label
      FROM pg_type t
      JOIN pg_enum e ON e.enumtypid=t.oid
      JOIN pg_namespace n ON n.oid=t.typnamespace
      WHERE n.nspname=%L AND t.typname=%L
      ORDER BY e.enumsortorder
    )
    SELECT COALESCE(
      (SELECT label FROM labels WHERE label = $1 LIMIT 1),
      (SELECT label FROM labels WHERE lower(label) IN ('update','updated','modify','modified','change','changed') LIMIT 1),
      (SELECT label FROM labels LIMIT 1)
    )
  $q$, op_enum_schema, op_enum_name)
  USING COALESCE(NULLIF(trim(p_action),''), '')
  INTO chosen_op;

  IF chosen_op IS NULL OR chosen_op = '' THEN
    -- If enum somehow has no labels (shouldn't happen)
    RETURN;
  END IF;

  INSERT INTO public.audit_logs (
    table_name,
    record_id,
    operation,
    changed_by,
    change_details
  ) VALUES (
    coalesce(nullif(trim(p_entity_type),''), 'purchase'),
    p_entity_id,
    chosen_op::public.audit_operation,
    p_actor_id,
    coalesce(p_payload, '{}'::jsonb)
  );

EXCEPTION
  WHEN others THEN
    -- Never block your main flow because auditing failed
    RETURN;
END;
$$;

COMMIT;
