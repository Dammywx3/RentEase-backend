#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"

echo "== Patch wallet_credit_from_splits(): infer org from payment reference =="
echo "DB: $DB"
echo ""

psql -d "$DB" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.wallet_credit_from_splits(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  pmt RECORD;

  v_org uuid;
  v_currency text;

  s RECORD;
  v_wallet uuid;
BEGIN
  -- Load payment
  SELECT
    p.id,
    p.reference_type,
    p.reference_id,
    p.currency
  INTO pmt
  FROM public.payments p
  WHERE p.id = p_payment_id
  LIMIT 1;

  IF pmt.id IS NULL THEN
    RAISE EXCEPTION 'Payment not found: %', p_payment_id;
  END IF;

  v_currency := COALESCE(pmt.currency, 'USD');

  -- ✅ Infer organization_id from reference (NO session dependency)
  v_org := NULL;

  IF pmt.reference_type = 'purchase' AND pmt.reference_id IS NOT NULL THEN
    SELECT pp.organization_id
    INTO v_org
    FROM public.property_purchases pp
    WHERE pp.id = pmt.reference_id
      AND pp.deleted_at IS NULL
    LIMIT 1;
  ELSIF pmt.reference_type = 'rent_invoice' AND pmt.reference_id IS NOT NULL THEN
    SELECT ri.organization_id
    INTO v_org
    FROM public.rent_invoices ri
    WHERE ri.id = pmt.reference_id
      AND ri.deleted_at IS NULL
    LIMIT 1;
  END IF;

  -- Fallback only if you still want it (safe)
  IF v_org IS NULL THEN
    v_org := current_organization_uuid();
  END IF;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Cannot resolve organization_id for payment %. Ensure reference table has organization_id, or set app.organization_id.', p_payment_id;
  END IF;

  -- For each split, find wallet and create wallet_transactions rows
  FOR s IN
    SELECT
      ps.split_type,
      ps.beneficiary_kind,
      ps.beneficiary_user_id,
      ps.amount,
      COALESCE(ps.currency, v_currency) AS currency
    FROM public.payment_splits ps
    WHERE ps.payment_id = p_payment_id
    ORDER BY ps.created_at ASC
  LOOP
    -- wallet resolution (your helper should already exist)
    IF s.beneficiary_kind = 'platform'::public.beneficiary_kind THEN
      v_wallet := public.find_wallet_account_id(v_org, 'platform', NULL);
    ELSE
      v_wallet := public.find_wallet_account_id(v_org, 'user', s.beneficiary_user_id);
    END IF;

    IF v_wallet IS NULL THEN
      RAISE EXCEPTION 'Missing wallet_account for org=% kind=% user=%', v_org, s.beneficiary_kind::text, s.beneficiary_user_id;
    END IF;

    INSERT INTO public.wallet_transactions(
      organization_id,
      wallet_account_id,
      txn_type,
      reference_type,
      reference_id,
      amount,
      currency,
      note
    )
    VALUES (
      v_org,
      v_wallet,
      CASE
        WHEN s.split_type = 'payee'::public.split_type THEN 'credit_payee'::public.wallet_transaction_type
        WHEN s.split_type = 'agent_markup'::public.split_type THEN 'credit_agent_markup'::public.wallet_transaction_type
        WHEN s.split_type = 'agent_commission'::public.split_type THEN 'credit_agent_commission'::public.wallet_transaction_type
        WHEN s.split_type = 'platform_fee'::public.split_type THEN 'credit_platform_fee'::public.wallet_transaction_type
        ELSE 'adjustment'::public.wallet_transaction_type
      END,
      'payment',
      p_payment_id,
      s.amount,
      s.currency,
      'Credit from payment ' || p_payment_id::text || ' (' || s.split_type::text || ')'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

END;
$$;

-- quick visibility
SELECT 'wallet_credit_from_splits patched' AS ok;
SQL

echo ""
echo "✅ Patched. Now retry your status update:"
echo "  psql -d $DB -X -v ON_ERROR_STOP=1 -c \"update public.payments set status='successful'::public.payment_status where id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid;\""
echo ""
echo "Then check credits:"
echo "  psql -d $DB -X -P pager=off -c \"select txn_type::text, amount, currency, reference_type, reference_id, created_at from public.wallet_transactions where reference_type='payment' order by created_at desc limit 50;\""
