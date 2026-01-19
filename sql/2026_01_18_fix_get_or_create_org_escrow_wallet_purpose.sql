-- Fix: get_or_create_org_escrow_wallet(uuid) for schema where wallet_accounts uses:
--   purpose wallet_account_purpose NOT NULL
--   is_platform_wallet boolean
--   user_id nullable
--
-- This version:
--   - detects which escrow-ish enum label exists
--   - finds existing org escrow wallet (user_id IS NULL)
--   - creates it if missing

CREATE OR REPLACE FUNCTION public.get_or_create_org_escrow_wallet(p_org_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_wallet_id uuid;

  -- Candidate purpose values we want (we'll pick the first that exists in enum)
  prefs text[] := ARRAY[
    'org_escrow',
    'escrow',
    'purchase_escrow',
    'escrow_wallet',
    'escrow_hold'
  ];
  chosen text;

  available text;
BEGIN
  -- 0) Ensure table exists
  IF to_regclass('public.wallet_accounts') IS NULL THEN
    RAISE EXCEPTION 'public.wallet_accounts does not exist';
  END IF;

  -- 1) Ensure purpose enum exists
  IF to_regtype('public.wallet_account_purpose') IS NULL THEN
    RAISE EXCEPTION 'public.wallet_account_purpose type does not exist';
  END IF;

  -- 2) Choose a valid enum label for escrow
  SELECT p
  INTO chosen
  FROM unnest(prefs) p
  WHERE EXISTS (
    SELECT 1
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'wallet_account_purpose'
      AND e.enumlabel = p
  )
  LIMIT 1;

  IF chosen IS NULL THEN
    SELECT string_agg(e.enumlabel, ', ' ORDER BY e.enumsortorder)
    INTO available
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public'
      AND t.typname = 'wallet_account_purpose';

    RAISE EXCEPTION
      'No escrow-like purpose found in enum public.wallet_account_purpose. Available labels: %',
      coalesce(available,'(none)');
  END IF;

  -- 3) Find existing org escrow wallet (org-owned, not platform wallet)
  SELECT id
  INTO v_wallet_id
  FROM public.wallet_accounts
  WHERE organization_id = p_org_id
    AND user_id IS NULL
    AND purpose::text = chosen
    AND coalesce(is_platform_wallet, false) = false
  LIMIT 1;

  IF v_wallet_id IS NOT NULL THEN
    RETURN v_wallet_id;
  END IF;

  -- 4) Create it (use defaults for currency/timestamps)
  INSERT INTO public.wallet_accounts (
    organization_id,
    user_id,
    is_platform_wallet,
    purpose
  ) VALUES (
    p_org_id,
    NULL,
    false,
    chosen::public.wallet_account_purpose
  )
  RETURNING id INTO v_wallet_id;

  RETURN v_wallet_id;
END;
$$;

-- Optional quick check:
-- SELECT public.get_or_create_org_escrow_wallet(current_organization_uuid());
