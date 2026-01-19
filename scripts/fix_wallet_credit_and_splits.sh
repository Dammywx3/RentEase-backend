#!/usr/bin/env bash
set -euo pipefail
DB="${DB:-rentease}"

echo "== Fix: wallet_credit_from_splits() org derivation + ensure_payment_splits() =="
echo "DB: $DB"
echo ""

psql -d "$DB" -X -v ON_ERROR_STOP=1 <<'SQL'
-- ============================================================
-- 1) Fix wallet_credit_from_splits(): remove pmt.organization_id
--    derive org from listing.organization_id
-- ============================================================
CREATE OR REPLACE FUNCTION public.wallet_credit_from_splits(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  pmt record;
  s record;

  v_org uuid;
  v_currency text;
  v_wallet uuid;

  v_txn_type public.wallet_transaction_type;
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

  -- payments has NO organization_id -> derive from listing (best)
  SELECT pl.organization_id
    INTO v_org
  FROM public.property_listings pl
  WHERE pl.id = pmt.listing_id
    AND pl.deleted_at IS NULL
  LIMIT 1;

  v_org := COALESCE(v_org, current_organization_uuid());
  v_currency := COALESCE(pmt.currency::text, 'USD');

  FOR s IN
    SELECT *
    FROM public.payment_splits
    WHERE payment_id = p_payment_id
    ORDER BY created_at ASC
  LOOP
    -- Resolve wallet account
    IF s.beneficiary_kind = 'platform'::public.beneficiary_kind THEN
      SELECT wa.id
        INTO v_wallet
      FROM public.wallet_accounts wa
      WHERE wa.organization_id = v_org
        AND wa.owner_kind = 'platform'::public.wallet_owner_kind
        AND wa.deleted_at IS NULL
      ORDER BY wa.created_at ASC
      LIMIT 1;
    ELSE
      SELECT wa.id
        INTO v_wallet
      FROM public.wallet_accounts wa
      WHERE wa.organization_id = v_org
        AND wa.owner_kind = 'user'::public.wallet_owner_kind
        AND wa.owner_user_id = s.beneficiary_user_id
        AND wa.deleted_at IS NULL
      ORDER BY wa.created_at ASC
      LIMIT 1;
    END IF;

    IF v_wallet IS NULL THEN
      RAISE EXCEPTION 'Wallet not found for split %, beneficiary_kind=%, beneficiary_user_id=%',
        s.id, s.beneficiary_kind, s.beneficiary_user_id;
    END IF;

    -- ENUM-safe txn_type mapping
    v_txn_type :=
      CASE
        WHEN s.split_type = 'payee'::public.split_type THEN 'credit_payee'::public.wallet_transaction_type
        WHEN s.split_type = 'agent_markup'::public.split_type THEN 'credit_agent_markup'::public.wallet_transaction_type
        WHEN s.split_type = 'agent_commission'::public.split_type THEN 'credit_agent_commission'::public.wallet_transaction_type
        WHEN s.split_type = 'platform_fee'::public.split_type THEN 'credit_platform_fee'::public.wallet_transaction_type
        ELSE 'adjustment'::public.wallet_transaction_type
      END;

    INSERT INTO public.wallet_transactions(
      organization_id, wallet_account_id, txn_type,
      reference_type, reference_id, amount, currency, note
    )
    VALUES (
      v_org, v_wallet, v_txn_type,
      'payment', pmt.id, s.amount, v_currency,
      'Credit from ' || pmt.transaction_reference || ' (' || s.split_type::text || ')'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
END;
$$;

-- ============================================================
-- 2) Ensure splits exist before setting payment successful
--    - purchase => payee = property_purchases.seller_id
--    - rent_invoice => payee = properties.owner_id
--    fee = 2.5%
-- ============================================================
CREATE OR REPLACE FUNCTION public.ensure_payment_splits(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  pmt record;
  v_currency text;

  v_payee_user_id uuid;
  v_fee numeric(15,2);
  v_net numeric(15,2);
  v_pct numeric := 2.5;
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

  -- if splits already exist, do nothing
  IF EXISTS (SELECT 1 FROM public.payment_splits ps WHERE ps.payment_id = p_payment_id) THEN
    RETURN;
  END IF;

  IF pmt.reference_type = 'purchase' AND pmt.reference_id IS NOT NULL THEN
    SELECT pp.seller_id
      INTO v_payee_user_id
    FROM public.property_purchases pp
    WHERE pp.id = pmt.reference_id
      AND pp.deleted_at IS NULL
    LIMIT 1;

  ELSIF pmt.reference_type = 'rent_invoice' AND pmt.reference_id IS NOT NULL THEN
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

  v_fee := round((pmt.amount * v_pct / 100.0)::numeric, 2);
  IF v_fee < 0 THEN v_fee := 0; END IF;

  v_net := round((pmt.amount - v_fee)::numeric, 2);
  IF v_net < 0 THEN v_net := 0; END IF;

  INSERT INTO public.payment_splits(
    payment_id, split_type, beneficiary_kind, beneficiary_user_id, amount, currency
  )
  VALUES
    (p_payment_id, 'platform_fee'::public.split_type, 'platform'::public.beneficiary_kind, NULL, v_fee, v_currency),
    (p_payment_id, 'payee'::public.split_type, 'user'::public.beneficiary_kind, v_payee_user_id, v_net, v_currency);
END;
$$;
SQL

echo "✅ Functions updated."
echo ""
echo "Now run these (example uses your payment id):"
echo "  psql -d $DB -X -v ON_ERROR_STOP=1 -c \"select public.ensure_payment_splits('b77e1471-ef74-43fe-baf7-1accd5717679'::uuid);\""
echo "  psql -d $DB -X -P pager=off -c \"select split_type::text, beneficiary_kind::text, beneficiary_user_id, amount, currency from public.payment_splits where payment_id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid;\""
echo "  psql -d $DB -X -v ON_ERROR_STOP=1 -c \"update public.payments set status='successful'::public.payment_status where id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid;\""
echo "  psql -d $DB -X -P pager=off -c \"select txn_type::text, amount, currency, reference_type, reference_id, created_at from public.wallet_transactions where reference_type='payment' order by created_at desc limit 20;\""
echo ""
