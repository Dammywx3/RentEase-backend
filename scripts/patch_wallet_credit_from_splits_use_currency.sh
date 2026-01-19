#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"

echo "== Patch wallet_credit_from_splits(): infer org + pass currency to wallet lookup =="
echo "DB: $DB"
echo ""

psql -d "$DB" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.wallet_credit_from_splits(p_payment_id uuid)
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  v_org uuid;
  v_ref_type text;
  v_ref_id uuid;

  s record;
  v_wallet uuid;
  v_kind text;
  v_user uuid;

  v_txn public.wallet_transaction_type;
BEGIN
  -- Load payment reference info (do NOT assume payments.organization_id exists)
  SELECT p.reference_type::text, p.reference_id
  INTO v_ref_type, v_ref_id
  FROM public.payments p
  WHERE p.id = p_payment_id
    AND p.deleted_at IS NULL;

  IF v_ref_type IS NULL THEN
    RAISE EXCEPTION 'payment not found: %', p_payment_id;
  END IF;

  -- 1) Try session org first (if your middleware sets it)
  BEGIN
    v_org := current_organization_uuid();
  EXCEPTION WHEN OTHERS THEN
    v_org := NULL noting;
  END;

  -- 2) If session org missing, infer org from the payment reference
  IF v_org IS NULL THEN
    IF v_ref_type = 'purchase' THEN
      SELECT organization_id INTO v_org
      FROM public.property_purchases
      WHERE id = v_ref_id
        AND deleted_at IS NULL
      LIMIT 1;
    ELSIF v_ref_type = 'rent_invoice' THEN
      SELECT organization_id INTO v_org
      FROM public.rent_invoices
      WHERE id = v_ref_id
        AND deleted_at IS NULL
      LIMIT 1;
    END IF;
  END IF;

  -- 3) Last fallback: infer from payment.property_id -> properties.organization_id (if available)
  IF v_org IS NULL THEN
    BEGIN
      SELECT pr.organization_id INTO v_org
      FROM public.payments p
      JOIN public.properties pr ON pr.id = p.property_id
      WHERE p.id = p_payment_id
        AND p.deleted_at IS NULL
        AND pr.deleted_at IS NULL
      LIMIT 1;
    EXCEPTION WHEN OTHERS THEN
      v_org := NULL;
    END;
  END IF;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'Cannot infer organization_id for payment %. Set app.organization_id or ensure reference tables have org.', p_payment_id;
  END IF;

  -- Must have splits before we credit
  IF NOT EXISTS (SELECT 1 FROM public.payment_splits ps WHERE ps.payment_id = p_payment_id) THEN
    RAISE EXCEPTION 'No payment_splits for payment %. Run ensure_payment_splits() before crediting.', p_payment_id;
  END IF;

  -- Write credits from each split
  FOR s IN
    SELECT
      ps.split_type,
      ps.beneficiary_kind,
      ps.beneficiary_user_id,
      ps.amount,
      ps.currency
    FROM public.payment_splits ps
    WHERE ps.payment_id = p_payment_id
    ORDER BY ps.created_at ASC
  LOOP
    v_kind := s.beneficiary_kind::text;
    v_user := s.beneficiary_user_id;

    -- pick wallet using org + kind + user + currency
    v_wallet := public.find_wallet_account_id(v_org, v_kind, v_user, s.currency::text);

    IF v_wallet IS NULL THEN
      RAISE EXCEPTION
        'No wallet_account found for org=% kind=% user=% currency=% (payment=% split_type=%)',
        v_org, v_kind, v_user, s.currency, p_payment_id, s.split_type::text;
    END IF;

    v_txn :=
      CASE
        WHEN s.split_type = 'payee'::public.split_type THEN 'credit_payee'::public.wallet_transaction_type
        WHEN s.split_type = 'agent_markup'::public.split_type THEN 'credit_agent_markup'::public.wallet_transaction_type
        WHEN s.split_type = 'agent_commission'::public.split_type THEN 'credit_agent_commission'::public.wallet_transaction_type
        WHEN s.split_type = 'platform_fee'::public.split_type THEN 'credit_platform_fee'::public.wallet_transaction_type
        ELSE 'adjustment'::public.wallet_transaction_type
      END;

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
      v_txn,
      'payment',
      p_payment_id,
      s.amount,
      s.currency,
      'Credit from payment ' || p_payment_id::text || ' (' || s.split_type::text || ')'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

END;
$function$;

SELECT 'wallet_credit_from_splits upgraded (org infer + currency wallet)' AS ok;
SQL

echo ""
echo "✅ Done."
echo ""
echo "Next test (example):"
echo "  psql -d $DB -X -v ON_ERROR_STOP=1 -c \"select public.ensure_payment_splits('b77e1471-ef74-43fe-baf7-1accd5717679'::uuid);\""
echo "  psql -d $DB -X -v ON_ERROR_STOP=1 -c \"update public.payments set status='successful'::public.payment_status where id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid;\""
echo "  psql -d $DB -X -P pager=off -c \"select txn_type::text, amount, currency, reference_type, reference_id, created_at from public.wallet_transactions where reference_type='payment' and reference_id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid order by created_at desc limit 50;\""
