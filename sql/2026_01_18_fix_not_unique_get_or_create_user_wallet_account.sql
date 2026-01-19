BEGIN;

-- Drop ALL possible 1-arg wrappers in public that match identity args = uuid
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid, n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='get_or_create_user_wallet_account'
      AND pg_get_function_identity_arguments(p.oid) = 'uuid'
  LOOP
    EXECUTE format('DROP FUNCTION IF EXISTS %I.%I(%s);', r.nspname, r.proname, r.args);
  END LOOP;
END $$;

-- Recreate ONE canonical wrapper
CREATE FUNCTION public.get_or_create_user_wallet_account(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.get_or_create_user_wallet_account(p_user_id, NULL, NULL);
$$;

COMMIT;
