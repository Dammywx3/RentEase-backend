#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"

echo "== Fix: wallet_credit_from_splits() enum txn_type =="
echo "DB: $DB"
echo ""

psql -d "$DB" -X -v ON_ERROR_STOP=1 <<'SQL'
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
  -- Load payment
  SELECT p.*
  INTO pmt
  FROM public.payments p
  WHERE p.id = p_payment_id
    AND p.deleted_at IS NULL
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment not found: %', p_payment_id;
  END IF;

  v_org := COALESCE(pmt.organization_id, current_organization_uuid());
  v_currency := COALESCE(pmt.currency::text, 'USD');

  -- For each split, credit the correct wallet
  FOR s IN
    SELECT *
    FROM public.payment_splits
    WHERE payment_id = p_payment_id
    ORDER BY created_at ASC
  LOOP
    -- Resolve wallet for beneficiary
    IF s.beneficiary_kind = 'platform'::public.beneficiary_kind THEN
      -- platform wallet
      SELECT wa.id
      INTO v_wallet
      FROM public.wallet_accounts wa
      WHERE wa.organization_id = v_org
        AND wa.owner_kind = 'platform'::public.wallet_owner_kind
        AND wa.deleted_at IS NULL
      ORDER BY wa.created_at ASC
      LIMIT 1;
    ELSE
      -- user wallet
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

    -- ✅ IMPORTANT: CASE returns ENUM (not text)
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
SQL

echo "✅ Patched wallet_credit_from_splits()"
echo ""

echo "== Quick checks =="
psql -d "$DB" -X -P pager=off -c "\df+ public.wallet_credit_from_splits" | sed -n '1,80p'
echo ""

echo "== Next: test the trigger path =="
echo "1) Pick a payment_id that has splits:"
echo "   psql -d $DB -X -P pager=off -c \"select payment_id, count(*) from public.payment_splits group by 1 order by 2 desc limit 10;\""
echo ""
echo "2) Then run (this simulates what the trigger does):"
echo "   psql -d $DB -X -v ON_ERROR_STOP=1 -c \"select public.wallet_credit_from_splits('PAYMENT_UUID_HERE'::uuid);\""
echo ""
echo "If that runs without error, then updating payments.status -> 'successful' will work too."
