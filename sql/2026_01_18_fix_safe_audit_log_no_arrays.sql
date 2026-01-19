BEGIN;

-- Make sure audit_operation exists (it does in your schema)
-- This function MUST NOT use any text[] casts.
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
  v_op public.audit_operation;
BEGIN
  -- Map the incoming text action into your enum safely
  BEGIN
    v_op := p_action::public.audit_operation;
  EXCEPTION WHEN others THEN
    -- fallback if caller passes non-enum values like "close_complete"
    v_op := 'update'::public.audit_operation;
  END;

  INSERT INTO public.audit_logs (
    table_name,
    record_id,
    operation,
    changed_by,
    change_details
  ) VALUES (
    coalesce(nullif(trim(p_entity_type),''), 'purchase'),
    p_entity_id,
    v_op,
    p_actor_id,
    coalesce(p_payload, '{}'::jsonb)
  );

EXCEPTION
  WHEN undefined_table OR undefined_column THEN
    -- if schema differs in some envs, do not break main flow
    RETURN;
END;
$$;

COMMIT;
