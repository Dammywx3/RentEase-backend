#!/usr/bin/env bash
set -euo pipefail

DB="${DB:-rentease}"

echo "== Fix wallet_credit_from_splits(): wallet_accounts column mismatch =="
echo "DB: $DB"
echo ""

echo "-> 1) Show wallet_accounts columns (so we patch correctly):"
psql -d "$DB" -X -P pager=off -c "
select
  column_name,
  data_type,
  udt_name,
  is_nullable
from information_schema.columns
where table_schema='public'
  and table_name='wallet_accounts'
order by ordinal_position;
"
echo ""

echo "-> 2) Install helper: public.find_wallet_account_id(org, kind, user_id)"
psql -d "$DB" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE OR REPLACE FUNCTION public.find_wallet_account_id(
  p_org uuid,
  p_beneficiary_kind text,
  p_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_id uuid;

  -- detected column names (if they exist)
  col_owner_kind text := NULL;
  col_user_id text := NULL;

  q text;
BEGIN
  -- detect "platform/user" discriminator column
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_kind'
  ) THEN
    col_owner_kind := 'owner_kind';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_type'
  ) THEN
    col_owner_kind := 'owner_type';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='wallet_owner_kind'
  ) THEN
    col_owner_kind := 'wallet_owner_kind';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='account_kind'
  ) THEN
    col_owner_kind := 'account_kind';
  END IF;

  -- detect user id column
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_user_id'
  ) THEN
    col_user_id := 'owner_user_id';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='user_id'
  ) THEN
    col_user_id := 'user_id';
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='wallet_accounts' AND column_name='owner_id'
  ) THEN
    col_user_id := 'owner_id';
  END IF;

  -- PLATFORM wallet lookup
  IF p_beneficiary_kind = 'platform' THEN
    -- Prefer explicit kind/type column if it exists
    IF col_owner_kind IS NOT NULL THEN
      q := format(
        'SELECT wa.id
         FROM public.wallet_accounts wa
         WHERE wa.organization_id = $1
           AND wa.%I::text = ''platform''
           AND wa.deleted_at IS NULL
         ORDER BY wa.created_at ASC
         LIMIT 1',
        col_owner_kind
      );
      EXECUTE q INTO v_id USING p_org;
      IF v_id IS NOT NULL THEN
        RETURN v_id;
      END IF;
    END IF;

    -- Fallback: platform wallet is a row with NULL user owner (if you use that model)
    IF col_user_id IS NOT NULL THEN
      q := format(
        'SELECT wa.id
         FROM public.wallet_accounts wa
         WHERE wa.organization_id = $1
           AND wa.%I IS NULL
           AND wa.deleted_at IS NULL
         ORDER BY wa.created_at ASC
         LIMIT 1',
        col_user_id
      );
      EXECUTE q INTO v_id USING p_org;
      RETURN v_id;
    END IF;

    RETURN NULL;
  END IF;

  -- USER wallet lookup
  IF p_beneficiary_kind = 'user' THEN
    IF col_user_id IS NULL THEN
      RETURN NULL;
    END IF;

    q := format(
      'SELECT wa.id
       FROM public.wallet_accounts wa
       WHERE wa.organization_id = $1
         AND wa.%I = $2
         AND wa.deleted_at IS NULL
       ORDER BY wa.created_at ASC
       LIMIT 1',
      col_user_id
    );
    EXECUTE q INTO v_id USING p_org, p_user_id;
    RETURN v_id;
  END IF;

  RETURN NULL;
END;
$$;
SQL
echo "✅ helper installed"
echo ""

echo "-> 3) Patch wallet_credit_from_splits() to use helper + correct txn enum casts"
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
  v_txn public.wallet_transaction_type;
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

  -- payments table has NO organization_id in your schema -> use context
  v_org := current_organization_uuid();
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'current_organization_uuid() is NULL. Set app.organization_id before triggering credits.';
  END IF;

  v_currency := COALESCE(pmt.currency::text, 'USD');

  -- Ensure splits exist
  PERFORM public.ensure_payment_splits(p_payment_id);

  FOR s IN
    SELECT *
    FROM public.payment_splits ps
    WHERE ps.payment_id = p_payment_id
    ORDER BY ps.created_at ASC
  LOOP
    -- map split_type -> wallet txn enum
    IF s.split_type::text = 'payee' THEN
      v_txn := 'credit_payee'::public.wallet_transaction_type;
    ELSIF s.split_type::text = 'platform_fee' THEN
      v_txn := 'credit_platform_fee'::public.wallet_transaction_type;
    ELSIF s.split_type::text = 'agent_markup' THEN
      v_txn := 'credit_agent_markup'::public.wallet_transaction_type;
    ELSIF s.split_type::text = 'agent_commission' THEN
      v_txn := 'credit_agent_commission'::public.wallet_transaction_type;
    ELSE
      v_txn := 'adjustment'::public.wallet_transaction_type;
    END IF;

    -- locate wallet account
    IF s.beneficiary_kind::text = 'platform' THEN
      v_wallet := public.find_wallet_account_id(v_org, 'platform', NULL);
    ELSE
      v_wallet := public.find_wallet_account_id(v_org, 'user', s.beneficiary_user_id);
    END IF;

    IF v_wallet IS NULL THEN
      RAISE EXCEPTION
        'No wallet account found for split: kind=% user_id=% org=% (check wallet_accounts rows)',
        s.beneficiary_kind::text, s.beneficiary_user_id, v_org;
    END IF;

    INSERT INTO public.wallet_transactions(
      organization_id, wallet_account_id, txn_type,
      reference_type, reference_id, amount, currency, note
    )
    VALUES (
      v_org, v_wallet, v_txn,
      'payment', pmt.id, s.amount, v_currency,
      'Credit from payment ' || pmt.transaction_reference || ' (' || s.split_type::text || ')'
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
END;
$$;
SQL
echo "✅ wallet_credit_from_splits patched"
echo ""

echo "-> 4) Quick show: wallet_accounts sample rows (top 10)"
psql -d "$DB" -X -P pager=off -c "
select *
from public.wallet_accounts
where deleted_at is null
order by created_at asc
limit 10;
" || true

echo ""
echo "== DONE =="
echo "Now retry your payment status update:"
echo "  psql -d $DB -X -v ON_ERROR_STOP=1 -c \"update public.payments set status='successful'::public.payment_status where id='b77e1471-ef74-43fe-baf7-1accd5717679'::uuid;\""
echo ""
echo "Then check credits:"
echo "  psql -d $DB -X -P pager=off -c \"select txn_type::text, amount, currency, reference_type, reference_id, created_at from public.wallet_transactions where reference_type='payment' order by created_at desc limit 20;\""
