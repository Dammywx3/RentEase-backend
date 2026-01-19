BEGIN;

-- 1) Add actor_id to parent (propagates to partitions in Postgres)
ALTER TABLE IF EXISTS public.audit_logs
  ADD COLUMN IF NOT EXISTS actor_id uuid;

-- 2) Backfill actor_id from changed_by where missing
UPDATE public.audit_logs
SET actor_id = changed_by
WHERE actor_id IS NULL
  AND changed_by IS NOT NULL;

-- 3) (Optional) keep them in sync going forward
-- If you want actor_id to be the source of truth, you can drop this.
CREATE OR REPLACE FUNCTION public.audit_logs_sync_actor_id()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.actor_id IS NULL AND NEW.changed_by IS NOT NULL THEN
    NEW.actor_id := NEW.changed_by;
  END IF;
  IF NEW.changed_by IS NULL AND NEW.actor_id IS NOT NULL THEN
    NEW.changed_by := NEW.actor_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_logs_sync_actor_id ON public.audit_logs;

CREATE TRIGGER trg_audit_logs_sync_actor_id
BEFORE INSERT OR UPDATE ON public.audit_logs
FOR EACH ROW
EXECUTE FUNCTION public.audit_logs_sync_actor_id();

COMMIT;