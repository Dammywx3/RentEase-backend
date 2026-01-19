#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

DB_NAME="${DB_NAME:-rentease}"

TS="$(date +%Y%m%d_%H%M%S)"
SQL="scripts/.tmp_patch_wallet_escrow_support.${TS}.sql"

cat > "$SQL" <<'SQL'
BEGIN;

DO $$
BEGIN
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'debit_buyer'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'credit_buyer'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'credit_escrow'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'debit_escrow'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'credit_seller'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'debit_seller'; EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN ALTER TYPE wallet_transaction_type ADD VALUE IF NOT EXISTS 'credit_platform_fee'; EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

ALTER TABLE public.property_purchases
  ADD COLUMN IF NOT EXISTS escrow_wallet_account_id uuid,
  ADD COLUMN IF NOT EXISTS escrow_held_amount numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escrow_released_amount numeric(12,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escrow_released_at timestamptz;

ALTER TABLE public.property_purchases
  ADD COLUMN IF NOT EXISTS deposit_amount numeric(12,2);

CREATE TABLE IF NOT EXISTS public.escrow_wallet_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES public.organizations(id),
  currency text NOT NULL,
  wallet_account_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, currency)
);

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

  INSERT INTO public.wallet_accounts (id, organization_id, currency, created_at)
  VALUES (gen_random_uuid(), p_org, p_currency, now())
  RETURNING id INTO v_wallet_id;

  INSERT INTO public.escrow_wallet_accounts (organization_id, currency, wallet_account_id)
  VALUES (p_org, p_currency, v_wallet_id);

  RETURN v_wallet_id;
END;
$$;

COMMIT;
SQL

echo "==> Applying $SQL to DB_NAME=$DB_NAME ..."
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$SQL"
echo "✅ Escrow wallet support patched."
