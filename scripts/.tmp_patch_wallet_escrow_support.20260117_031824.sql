BEGIN;

-- ============================================================
-- 1) Add enum values for wallet_transaction_type (safe)
--    NOTE: If your enum name differs, update it here.
-- ============================================================
DO $$
BEGIN
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'debit_buyer'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'credit_buyer'; EXCEPTION WHEN duplicate_object THEN NULL; END;

  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'credit_escrow'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'debit_escrow'; EXCEPTION WHEN duplicate_object THEN NULL; END;

  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'credit_seller'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'debit_seller'; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- ============================================================
-- 2) Add escrow fields to property_purchases (safe)
-- ============================================================
ALTER TABLE public.property_purchases
  ADD COLUMN IF NOT EXISTS escrow_wallet_account_id uuid,
  ADD COLUMN IF NOT EXISTS escrow_held_amount numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escrow_released_amount numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escrow_released_at timestamptz;

-- Optional deposit amount for staged escrow
ALTER TABLE public.property_purchases
  ADD COLUMN IF NOT EXISTS deposit_amount numeric(12,2);

-- ============================================================
-- 3) Escrow wallet registry per org+currency (safe)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.escrow_wallet_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  currency text NOT NULL,
  wallet_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, currency)
);

-- ============================================================
-- 4) Helper: get_or_create escrow wallet account
--    Assumes you have public.wallet_accounts table with:
--      id uuid, organization_id uuid, currency text, created_at timestamptz, ...
--    If your wallet_accounts schema differs, tell me and I’ll adapt it.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_or_create_org_escrow_wallet(
  p_org uuid,
  p_currency text
) RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_wallet_id uuid;
BEGIN
  SELECT e.wallet_account_id
    INTO v_wallet_id
  FROM public.escrow_wallet_accounts e
  WHERE e.organization_id = p_org
    AND e.currency = p_currency
  LIMIT 1;

  IF v_wallet_id IS NOT NULL THEN
    RETURN v_wallet_id;
  END IF;

  -- Create escrow wallet account (minimal insert)
  INSERT INTO public.wallet_accounts (id, organization_id, currency, created_at)
  VALUES (gen_random_uuid(), p_org, p_currency, now())
  RETURNING id INTO v_wallet_id;

  INSERT INTO public.escrow_wallet_accounts (organization_id, currency, wallet_account_id)
  VALUES (p_org, p_currency, v_wallet_id);

  RETURN v_wallet_id;
END;
$$;

COMMIT;
