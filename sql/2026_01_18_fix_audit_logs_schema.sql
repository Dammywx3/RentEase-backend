BEGIN;

-- Ensure table exists (won't overwrite an existing one)
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id uuid PRIMARY KEY DEFAULT rentease_uuid(),
  created_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE
  has_org_id boolean;
  has_org_uuid boolean;
  has_org boolean;
  has_actor boolean;
  has_action boolean;
  has_entity_type boolean;
  has_entity_id boolean;
  has_payload boolean;
  has_created_at boolean;
BEGIN
  -- detect columns
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='organization_id')
    INTO has_org_id;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='organization_uuid')
    INTO has_org_uuid;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='org_id')
    INTO has_org;

  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='actor_user_id')
    INTO has_actor;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='action')
    INTO has_action;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_type')
    INTO has_entity_type;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='entity_id')
    INTO has_entity_id;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='payload')
    INTO has_payload;
  SELECT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='audit_logs' AND column_name='created_at')
    INTO has_created_at;

  -- Add organization_id if missing
  IF NOT has_org_id THEN
    ALTER TABLE public.audit_logs ADD COLUMN organization_id uuid;
    -- backfill from other possible org cols
    IF has_org_uuid THEN
      EXECUTE 'UPDATE public.audit_logs SET organization_id = organization_uuid WHERE organization_id IS NULL';
    ELSIF has_org THEN
      EXECUTE 'UPDATE public.audit_logs SET organization_id = org_id WHERE organization_id IS NULL';
    END IF;

    -- set default + not null AFTER backfill
    BEGIN
      EXECUTE 'ALTER TABLE public.audit_logs ALTER COLUMN organization_id SET DEFAULT current_organization_uuid()';
    EXCEPTION WHEN others THEN
      -- if current_organization_uuid() doesn't exist in this DB, ignore
      NULL;
    END;

    EXECUTE 'UPDATE public.audit_logs SET organization_id = COALESCE(organization_id, current_organization_uuid()) WHERE organization_id IS NULL';

    ALTER TABLE public.audit_logs ALTER COLUMN organization_id SET NOT NULL;

    -- FK (safe)
    BEGIN
      ALTER TABLE public.audit_logs
        ADD CONSTRAINT audit_logs_organization_id_fkey
        FOREIGN KEY (organization_id) REFERENCES public.organizations(id);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    WHEN undefined_table THEN
      NULL;
    END;
  END IF;

  -- Add actor_user_id if missing
  IF NOT has_actor THEN
    ALTER TABLE public.audit_logs ADD COLUMN actor_user_id uuid;
    BEGIN
      ALTER TABLE public.audit_logs
        ADD CONSTRAINT audit_logs_actor_user_id_fkey
        FOREIGN KEY (actor_user_id) REFERENCES public.users(id);
    EXCEPTION WHEN duplicate_object THEN
      NULL;
    WHEN undefined_table THEN
      NULL;
    END;
  END IF;

  -- Add action if missing
  IF NOT has_action THEN
    ALTER TABLE public.audit_logs ADD COLUMN action text;
    UPDATE public.audit_logs SET action = COALESCE(action, 'unknown') WHERE action IS NULL;
    ALTER TABLE public.audit_logs ALTER COLUMN action SET NOT NULL;
  END IF;

  -- Add entity_type/entity_id if missing
  IF NOT has_entity_type THEN
    ALTER TABLE public.audit_logs ADD COLUMN entity_type text;
  END IF;
  IF NOT has_entity_id THEN
    ALTER TABLE public.audit_logs ADD COLUMN entity_id uuid;
  END IF;

  -- Add payload if missing
  IF NOT has_payload THEN
    ALTER TABLE public.audit_logs ADD COLUMN payload jsonb NOT NULL DEFAULT '{}'::jsonb;
  ELSE
    -- make sure payload not null + has default
    BEGIN
      ALTER TABLE public.audit_logs ALTER COLUMN payload SET DEFAULT '{}'::jsonb;
    EXCEPTION WHEN others THEN NULL; END;
    BEGIN
      UPDATE public.audit_logs SET payload = '{}'::jsonb WHERE payload IS NULL;
      ALTER TABLE public.audit_logs ALTER COLUMN payload SET NOT NULL;
    EXCEPTION WHEN others THEN NULL; END;
  END IF;

  -- Ensure created_at exists
  IF NOT has_created_at THEN
    ALTER TABLE public.audit_logs ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
  END IF;
END $$;

-- Indexes (safe now)
CREATE INDEX IF NOT EXISTS idx_audit_logs_org_created ON public.audit_logs(organization_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id, created_at DESC);

COMMIT;
