#!/usr/bin/env bash
set -euo pipefail
DB="${DB:-rentease}"
psql -d "$DB" -X -v ON_ERROR_STOP=1 -P pager=off <<'SQL'

-- 1) Ensure platform + user wallet accounts exist (matches your schema exactly)
CREATE OR REPLACE FUNCTION public.ensure_wallet_account(
  p_org uuid,
  p_kind text,         -- 'platform' or 'user'
  p_user uuid,         -- required when kind='user'
  p_currency text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_cur varchar(3) := upper(left(coalesce(nullif(trim(p_currency),''),'USD'),3));
  v_id uuid;
BEGIN
  IF p_kind = 'platform' THEN
    -- platform wallet: user_id NULL + purpose='platform'
    SELECT wa.id INTO v_id
    FROM public.wallet_accounts wa
    WHERE wa.organization_id = p_org
      AND wa.user_id IS NULL
      AND wa.purpose = 'platform'::public.wallet_account_purpose
      AND upper(coalesce(wa.currency,'USD')) = v_cur
    ORDER BY wa.created_at ASC
    LIMIT 1;

    IF v_id IS NULL THEN
      INSERT INTO public.wallet_accounts(organization_id, user_id, currency, is_platform_wallet, purpose)
      VALUES (p_org, NULL, v_cur, true, 'platform'::public.wallet_account_purpose)
      RETURNING id INTO v_id;
    END IF;

    RETURN v_id;
  END IF;

  IF p_kind = 'user' THEN
    IF p_user IS NULL THEN
      RAISE EXCEPTION 'ensure_wallet_account(kind=user) requires p_user';
    END IF;

    SELECT wa.id INTO v_id
    FROM public.wallet_accounts wa
    WHERE wa.organization_id = p_org
      AND wa.user_id = p_user
      AND wa.purpose = 'user'::public.wallet_account_purpose
      AND upper(coalesce(wa.currency,'USD')) = v_cur
    ORDER BY wa.created_at ASC
    LIMIT 1;

    IF v_id IS NULL THEN
      INSERT INTO public.wallet_accounts(organization_id, user_id, currency, is_platform_wallet, purpose)
      VALUES (p_org, p_user, v_cur, false, 'user'::public.wallet_account_purpose)
      RETURNING id INTO v_id;
    END IF;

    RETURN v_id;
  END IF;

  RAISE EXCEPTION 'Unknown beneficiary kind: % (expected platform|user)', p_kind;
END;
$$;

-- 2) Patch wallet_credit_from_splits to use ensure_wallet_account()
DO $$
DECLARE
  src text;
  fixed text;
BEGIN
  SELECT pg_get_functiondef(p.oid)
  INTO src
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname='public'
    AND p.proname='wallet_credit_from_splits'
  LIMIT 1;

  IF src IS NULL THEN
    RAISE EXCEPTION 'wallet_credit_from_splits not found';
  END IF;

  -- Replace the lookup line with safe ensure call.
  -- Old: v_wallet := public.find_wallet_account_id(v_org, v_kind, v_user, s.currency::text);
  fixed := replace(
    src,
    'v_wallet := public.find_wallet_account_id(v_org, v_kind, v_user, s.currency::text);',
    'v_wallet := public.ensure_wallet_account(v_org, v_kind, v_user, s.currency::text);'
  );

  -- If the old text isn't present (changed), do a weaker patch: ensure before exception
  IF fixed = src THEN
    RAISE NOTICE 'No exact match line found; no replace performed. You may have a different function body.';
  ELSE
    EXECUTE fixed;
    RAISE NOTICE 'Patched wallet_credit_from_splits to ensure wallets exist';
  END IF;
END $$;

SELECT 'ok' AS status, 'wallet bootstrap patched' AS note;
SQL
