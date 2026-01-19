#!/usr/bin/env bash
set -euo pipefail

SQL_FILE="sql/2026_01_18_fix_get_or_create_user_wallet_account_drop_recreate.sql"

echo "==> Writing migration: $SQL_FILE"

cat > "$SQL_FILE" <<'SQL'
-- Fix get_or_create_user_wallet_account helpers
-- - Drops existing functions to avoid "cannot change name of input parameter"
-- - Recreates with safe org resolution to prevent FK violations

BEGIN;

-- Drop first so we can recreate with any parameter names safely
DROP FUNCTION IF EXISTS public.get_or_create_user_wallet_account(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.get_or_create_user_wallet_account(uuid);

-- Main function (3-arg)
CREATE FUNCTION public.get_or_create_user_wallet_account(
  p_user_id uuid,
  p_org uuid DEFAULT NULL,
  p_currency text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_wallet_id uuid;
  v_org_id uuid;
  v_currency text;
  v_org_exists boolean;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required';
  END IF;

  -- normalize currency (optional)
  v_currency := NULLIF(btrim(coalesce(p_currency, '')), '');
  IF v_currency IS NOT NULL THEN
    v_currency := upper(v_currency);
  END IF;

  -- 1) Resolve a VALID organization_id
  v_org_id := p_org;

  IF v_org_id IS NOT NULL THEN
    SELECT EXISTS (SELECT 1 FROM public.organizations o WHERE o.id = v_org_id)
      INTO v_org_exists;

    -- If caller passed an org that does NOT exist, ignore it
    IF NOT v_org_exists THEN
      v_org_id := NULL;
    END IF;
  END IF;

  -- Fallback to user's organization_id
  IF v_org_id IS NULL THEN
    SELECT u.organization_id
      INTO v_org_id
    FROM public.users u
    WHERE u.id = p_user_id
      AND u.deleted_at IS NULL
    LIMIT 1;
  END IF;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Cannot resolve organization_id for user %', p_user_id;
  END IF;

  -- 2) Try to find existing wallet (prefer currency match)
  IF v_currency IS NOT NULL THEN
    SELECT wa.id
      INTO v_wallet_id
    FROM public.wallet_accounts wa
    WHERE wa.organization_id = v_org_id
      AND wa.user_id = p_user_id
      AND wa.purpose::text = 'user'
      AND coalesce(wa.is_platform_wallet,false) = false
      AND upper(coalesce(wa.currency,'USD')) = v_currency
    ORDER BY wa.created_at DESC
    LIMIT 1;

    IF v_wallet_id IS NOT NULL THEN
      RETURN v_wallet_id;
    END IF;
  END IF;

  -- fallback: any user wallet in that org
  SELECT wa.id
    INTO v_wallet_id
  FROM public.wallet_accounts wa
  WHERE wa.organization_id = v_org_id
    AND wa.user_id = p_user_id
    AND wa.purpose::text = 'user'
    AND coalesce(wa.is_platform_wallet,false) = false
  ORDER BY wa.created_at DESC
  LIMIT 1;

  IF v_wallet_id IS NOT NULL THEN
    RETURN v_wallet_id;
  END IF;

  -- 3) Create wallet with VALID org_id (prevents FK violation)
  INSERT INTO public.wallet_accounts (
    organization_id,
    user_id,
    is_platform_wallet,
    purpose,
    currency
  ) VALUES (
    v_org_id,
    p_user_id,
    false,
    'user'::public.wallet_account_purpose,
    coalesce(v_currency, 'USD')
  )
  RETURNING id INTO v_wallet_id;

  RETURN v_wallet_id;
END;
$$;

-- 1-arg wrapper (backwards compatible)
CREATE FUNCTION public.get_or_create_user_wallet_account(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.get_or_create_user_wallet_account(p_user_id, NULL, NULL);
$$;

COMMIT;
SQL

echo "✅ Migration written."
echo
echo "NEXT:"
echo "  DB=rentease psql -X -P pager=off -d \"\$DB\" -f $SQL_FILE"
