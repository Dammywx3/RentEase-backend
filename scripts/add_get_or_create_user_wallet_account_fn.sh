#!/usr/bin/env bash
set -euo pipefail

SQL_FILE="sql/2026_01_18_add_get_or_create_user_wallet_account.sql"

echo "==> Writing migration: $SQL_FILE"

cat > "$SQL_FILE" <<'SQL'
-- Adds missing helper used by purchase escrow release:
--   public.get_or_create_user_wallet_account(uuid)
--
-- Your schema:
--   wallet_accounts(
--     id uuid pk,
--     organization_id uuid NOT NULL default current_organization_uuid(),
--     user_id uuid NULL,
--     currency varchar default 'USD',
--     is_platform_wallet boolean default false,
--     purpose wallet_account_purpose NOT NULL default 'user'
--   )
--
-- Behavior:
--   - Finds an existing user wallet (purpose='user', is_platform_wallet=false)
--   - If p_org_id provided, scopes to that org
--   - If p_currency provided, prefers that currency
--   - Creates wallet if missing

CREATE OR REPLACE FUNCTION public.get_or_create_user_wallet_account(
  p_user_id uuid,
  p_org_id uuid DEFAULT NULL,
  p_currency text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_wallet_id uuid;
  v_currency text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required';
  END IF;

  -- normalize currency (optional)
  v_currency := NULLIF(btrim(coalesce(p_currency, '')), '');
  IF v_currency IS NOT NULL THEN
    v_currency := upper(v_currency);
  END IF;

  -- 1) Try find wallet by (org, user, purpose=user) and currency preference
  IF p_org_id IS NOT NULL THEN
    -- prefer exact currency match first
    IF v_currency IS NOT NULL THEN
      SELECT id INTO v_wallet_id
      FROM public.wallet_accounts
      WHERE organization_id = p_org_id
        AND user_id = p_user_id
        AND purpose::text = 'user'
        AND coalesce(is_platform_wallet,false) = false
        AND upper(coalesce(currency,'USD')) = v_currency
      ORDER BY created_at DESC
      LIMIT 1;

      IF v_wallet_id IS NOT NULL THEN
        RETURN v_wallet_id;
      END IF;
    END IF;

    -- fallback: any user wallet in that org
    SELECT id INTO v_wallet_id
    FROM public.wallet_accounts
    WHERE organization_id = p_org_id
      AND user_id = p_user_id
      AND purpose::text = 'user'
      AND coalesce(is_platform_wallet,false) = false
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_wallet_id IS NOT NULL THEN
      RETURN v_wallet_id;
    END IF;

    -- 2) Create in org
    INSERT INTO public.wallet_accounts (
      organization_id,
      user_id,
      is_platform_wallet,
      purpose,
      currency
    ) VALUES (
      p_org_id,
      p_user_id,
      false,
      'user'::public.wallet_account_purpose,
      coalesce(v_currency, 'USD')
    )
    RETURNING id INTO v_wallet_id;

    RETURN v_wallet_id;
  END IF;

  -- If org not provided: try find any wallet for user (any org), prefer currency
  IF v_currency IS NOT NULL THEN
    SELECT id INTO v_wallet_id
    FROM public.wallet_accounts
    WHERE user_id = p_user_id
      AND purpose::text = 'user'
      AND coalesce(is_platform_wallet,false) = false
      AND upper(coalesce(currency,'USD')) = v_currency
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_wallet_id IS NOT NULL THEN
      RETURN v_wallet_id;
    END IF;
  END IF;

  SELECT id INTO v_wallet_id
  FROM public.wallet_accounts
  WHERE user_id = p_user_id
    AND purpose::text = 'user'
    AND coalesce(is_platform_wallet,false) = false
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_wallet_id IS NOT NULL THEN
    RETURN v_wallet_id;
  END IF;

  -- Last resort: create without org (will use default current_organization_uuid())
  INSERT INTO public.wallet_accounts (
    user_id,
    is_platform_wallet,
    purpose,
    currency
  ) VALUES (
    p_user_id,
    false,
    'user'::public.wallet_account_purpose,
    coalesce(v_currency, 'USD')
  )
  RETURNING id INTO v_wallet_id;

  RETURN v_wallet_id;
END;
$$;

-- Backwards compatible wrapper (if caller uses the 1-arg version)
CREATE OR REPLACE FUNCTION public.get_or_create_user_wallet_account(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.get_or_create_user_wallet_account(p_user_id, NULL, NULL);
$$;
SQL

echo "✅ Migration written."
echo
echo "NEXT:"
echo "  DB=rentease psql -X -P pager=off -d \"\$DB\" -f $SQL_FILE"
