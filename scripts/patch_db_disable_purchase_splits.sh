#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?Missing DATABASE_URL}"

say() { printf "\n\033[1m%s\033[0m\n" "$*"; }
ok() { printf "✅ %s\n" "$*"; }
die() { printf "❌ %s\n" "$*"; exit 1; }

say "Patching DB: disable splits-crediting for purchase payments"
psql "$DATABASE_URL" -P pager=off -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;

-- 1) Patch trigger fn: skip purchases (webhook/finalize handles escrow hold)
CREATE OR REPLACE FUNCTION public.payments_success_trigger_fn()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status = 'successful' AND OLD.status IS DISTINCT FROM NEW.status THEN

    -- IMPORTANT:
    -- Purchases are handled by escrow functions after verification (webhook/finalize),
    -- so we must not auto-credit via splits (avoids double-credit + wrong ledger semantics).
    IF COALESCE(NEW.reference_type, '') = 'purchase' THEN
      RETURN NEW;
    END IF;

    PERFORM public.ensure_payment_splits(NEW.id);
    PERFORM public.wallet_credit_from_splits(NEW.id);
  END IF;

  RETURN NEW;
END;
$function$;

-- 2) Patch ensure_payment_splits: do nothing for purchases
CREATE OR REPLACE FUNCTION public.ensure_payment_splits(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  pmt record;
  v_currency text;

  v_payee_user_id uuid;
  v_fee numeric(15,2);
  v_net numeric(15,2);
BEGIN
  SELECT p.*
  INTO pmt
  FROM public.payments p
  WHERE p.id = p_payment_id
    AND p.deleted_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found: %', p_payment_id;
  END IF;

  v_currency := COALESCE(pmt.currency::text, 'USD');

  -- ✅ PURCHASES: escrow-driven, NOT split-driven
  IF COALESCE(pmt.reference_type, '') = 'purchase' THEN
    RETURN;
  END IF;

  -- if splits already exist, do nothing
  IF EXISTS (SELECT 1 FROM public.payment_splits ps WHERE ps.payment_id = p_payment_id) THEN
    RETURN;
  END IF;

  -- Resolve payee user
  IF pmt.reference_type = 'rent_invoice' AND pmt.reference_id IS NOT NULL THEN
    SELECT pr.owner_id
      INTO v_payee_user_id
    FROM public.rent_invoices ri
    JOIN public.properties pr ON pr.id = ri.property_id
    WHERE ri.id = pmt.reference_id
      AND ri.deleted_at IS NULL
    LIMIT 1;

  ELSE
    SELECT pr.owner_id
      INTO v_payee_user_id
    FROM public.properties pr
    WHERE pr.id = pmt.property_id
      AND pr.deleted_at IS NULL
    LIMIT 1;
  END IF;

  IF v_payee_user_id IS NULL THEN
    RAISE EXCEPTION 'Cannot resolve payee_user_id for payment % (ref_type=% ref_id=%)',
      p_payment_id, pmt.reference_type, pmt.reference_id;
  END IF;

  -- Fee/net come from app via payments columns
  v_fee := COALESCE(pmt.platform_fee_amount, 0)::numeric(15,2);
  v_net := COALESCE(pmt.payee_amount, (pmt.amount - v_fee))::numeric(15,2);

  IF v_fee < 0 OR v_net < 0 THEN
    RAISE EXCEPTION 'Invalid fee/net: platform_fee_amount=% payee_amount=% for payment=%',
      pmt.platform_fee_amount, pmt.payee_amount, p_payment_id;
  END IF;

  INSERT INTO public.payment_splits(
    payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency
  )
  VALUES
    (p_payment_id, 'platform_fee'::public.split_type, 'platform'::public.beneficiary_kind, NULL, v_fee, v_currency),
    (p_payment_id, 'payee'::public.split_type, 'user'::public.beneficiary_kind, v_payee_user_id, v_net, v_currency);
END;
$function$;

COMMIT;
SQL

ok "DB patch applied."
say "Sanity check:"
psql "$DATABASE_URL" -P pager=off -c "select pg_get_functiondef('public.payments_success_trigger_fn()'::regprocedure);" | sed -n '1,120p'
psql "$DATABASE_URL" -P pager=off -c "select pg_get_functiondef('public.ensure_payment_splits(uuid)'::regprocedure);" | sed -n '1,180p'
ok "Done."