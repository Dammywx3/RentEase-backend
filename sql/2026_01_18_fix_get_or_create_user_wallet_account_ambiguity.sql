BEGIN;

-- 0) Show what exists BEFORE (for logs)
-- (Safe: doesn't stop migration)
DO $$
BEGIN
  RAISE NOTICE 'Before fix:';
END $$;

-- 1) Drop the 1-arg wrapper if it exists
DROP FUNCTION IF EXISTS public.get_or_create_user_wallet_account(uuid);

-- 2) Drop the 3-arg version (we will recreate it WITHOUT defaults to avoid ambiguity)
DROP FUNCTION IF EXISTS public.get_or_create_user_wallet_account(uuid, uuid, text);

-- 3) Recreate the 3-arg function WITHOUT defaults (so calling with 1 arg is NOT possible)
CREATE FUNCTION public.get_or_create_user_wallet_account(
  p_user_id uuid,
  p_org_id uuid,
  p_currency text
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_wallet_id uuid;
  v_org_id uuid;
  v_currency text;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'p_user_id is required';
  END IF;

  v_currency := NULLIF(trim(coalesce(p_currency, '')), '');

  -- Determine org_id
  IF p_org_id IS NOT NULL THEN
    v_org_id := p_org_id;
  ELSE
    SELECT u.organization_id
      INTO v_org_id
    FROM public.users u
    WHERE u.id = p_user_id
    LIMIT 1;
  END IF;

  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Could not determine organization_id for user %', p_user_id;
  END IF;

  -- Find existing user wallet
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

  -- Create wallet
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

-- 4) Recreate ONE canonical 1-arg wrapper (used by your services)
CREATE FUNCTION public.get_or_create_user_wallet_account(p_user_id uuid)
RETURNS uuid
LANGUAGE sql
AS $$
  SELECT public.get_or_create_user_wallet_account(p_user_id, NULL::uuid, NULL::text);
$$;

COMMIT;
