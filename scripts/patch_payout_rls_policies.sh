#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?DATABASE_URL is not set}"

echo "Applying payout RLS policy patch..."

psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
BEGIN;

-- Ensure RLS is enabled and forced (safe if already true)
ALTER TABLE IF EXISTS public.payout_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.payout_accounts FORCE ROW LEVEL SECURITY;

ALTER TABLE IF EXISTS public.payouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.payouts FORCE ROW LEVEL SECURITY;

DO $$
DECLARE
  has_org_accounts boolean;
  has_deleted_accounts boolean;

  has_org_payouts boolean;
  has_deleted_payouts boolean;

  cond_org_accounts text;
  cond_not_deleted_accounts text;

  cond_org_payouts text;
  cond_not_deleted_payouts text;

  cond_actor text;
BEGIN
  -- Optional service bypass aligned with your other tables (won't break if role doesn't exist)
  cond_actor := '(user_id = current_user_uuid()) OR is_admin() OR (CURRENT_USER = ''rentease_service''::name)';

  -- ---- payout_accounts column detection
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='payout_accounts' AND column_name='organization_id'
  ) INTO has_org_accounts;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='payout_accounts' AND column_name='deleted_at'
  ) INTO has_deleted_accounts;

  cond_org_accounts := CASE
    WHEN has_org_accounts THEN '(organization_id = current_organization_uuid())'
    ELSE 'TRUE'
  END;

  cond_not_deleted_accounts := CASE
    WHEN has_deleted_accounts THEN '(deleted_at IS NULL)'
    ELSE 'TRUE'
  END;

  -- ---- payouts column detection
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='payouts' AND column_name='organization_id'
  ) INTO has_org_payouts;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='payouts' AND column_name='deleted_at'
  ) INTO has_deleted_payouts;

  cond_org_payouts := CASE
    WHEN has_org_payouts THEN '(organization_id = current_organization_uuid())'
    ELSE 'TRUE'
  END;

  cond_not_deleted_payouts := CASE
    WHEN has_deleted_payouts THEN '(deleted_at IS NULL)'
    ELSE 'TRUE'
  END;

  -- ============================================================
  -- payout_accounts policies (recreate clean & org-aware if possible)
  -- ============================================================
  EXECUTE 'DROP POLICY IF EXISTS payout_accounts_select ON public.payout_accounts;';
  EXECUTE 'DROP POLICY IF EXISTS payout_accounts_insert ON public.payout_accounts;';
  EXECUTE 'DROP POLICY IF EXISTS payout_accounts_update ON public.payout_accounts;';
  EXECUTE 'DROP POLICY IF EXISTS payout_accounts_delete ON public.payout_accounts;';

  EXECUTE format($pol$
    CREATE POLICY payout_accounts_select
    ON public.payout_accounts
    FOR SELECT
    USING (%s AND %s AND (%s));
  $pol$, cond_org_accounts, cond_not_deleted_accounts, cond_actor);

  EXECUTE format($pol$
    CREATE POLICY payout_accounts_insert
    ON public.payout_accounts
    FOR INSERT
    WITH CHECK (%s AND (%s));
  $pol$, cond_org_accounts, cond_actor);

  EXECUTE format($pol$
    CREATE POLICY payout_accounts_update
    ON public.payout_accounts
    FOR UPDATE
    USING (%s AND %s AND (%s))
    WITH CHECK (%s AND (%s));
  $pol$, cond_org_accounts, cond_not_deleted_accounts, cond_actor, cond_org_accounts, cond_actor);

  EXECUTE format($pol$
    CREATE POLICY payout_accounts_delete
    ON public.payout_accounts
    FOR DELETE
    USING (%s AND %s AND (%s));
  $pol$, cond_org_accounts, cond_not_deleted_accounts, cond_actor);

  -- ============================================================
  -- payouts policies (main fix: add SELECT; keep admin-update; keep owner insert)
  -- ============================================================
  EXECUTE 'DROP POLICY IF EXISTS payouts_select ON public.payouts;';
  EXECUTE 'DROP POLICY IF EXISTS payouts_insert ON public.payouts;';
  EXECUTE 'DROP POLICY IF EXISTS payouts_update_admin ON public.payouts;';
  EXECUTE 'DROP POLICY IF EXISTS payouts_delete_admin ON public.payouts;';

  -- ✅ This is what you were missing:
  EXECUTE format($pol$
    CREATE POLICY payouts_select
    ON public.payouts
    FOR SELECT
    USING (%s AND %s AND (%s));
  $pol$, cond_org_payouts, cond_not_deleted_payouts, cond_actor);

  -- allow user/admin/service to insert their own rows
  EXECUTE format($pol$
    CREATE POLICY payouts_insert
    ON public.payouts
    FOR INSERT
    WITH CHECK (%s AND (%s));
  $pol$, cond_org_payouts, cond_actor);

  -- keep admin/service updates only (matches what you already intended)
  EXECUTE $pol$
    CREATE POLICY payouts_update_admin
    ON public.payouts
    FOR UPDATE
    USING (is_admin() OR (CURRENT_USER = 'rentease_service'::name))
    WITH CHECK (is_admin() OR (CURRENT_USER = 'rentease_service'::name));
  $pol$;

  -- optional admin/service delete (safe + consistent)
  EXECUTE $pol$
    CREATE POLICY payouts_delete_admin
    ON public.payouts
    FOR DELETE
    USING (is_admin() OR (CURRENT_USER = 'rentease_service'::name));
  $pol$;

END $$;

COMMIT;

-- Show policies after patch
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname='public' AND tablename IN ('payout_accounts','payouts')
ORDER BY tablename, policyname;
SQL

echo "DONE ✅ payout RLS patched."