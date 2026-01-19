#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="$REPO_ROOT/.patch_backups/$TS"
mkdir -p "$BACKUP_DIR"

echo "Repo: $REPO_ROOT"
echo "Backups: $BACKUP_DIR"

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "[ERROR] DATABASE_URL not set. Run: set -a; source .env; set +a" >&2
  exit 1
fi

OUT="$BACKUP_DIR/wallet_credit_from_splits_before.sql"
psql "$DATABASE_URL" -P pager=off -c "select pg_get_functiondef('public.wallet_credit_from_splits(uuid)'::regprocedure);" > "$OUT"
echo "✅ Saved current function to: $OUT"

echo "Applying patch..."
psql "$DATABASE_URL" -P pager=off <<'SQL'
BEGIN;

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

  v_ins_ref_type text;
  v_ins_ref_id uuid;
BEGIN
  -- Load payment reference info
  SELECT p.reference_type::text, p.reference_id
  INTO v_ref_type, v_ref_id
  FROM public.payments p
  WHERE p.id = p_payment_id
    AND p.deleted_at IS NULL;

  IF v_ref_type IS NULL THEN
    RAISE EXCEPTION 'payment not found: %', p_payment_id;
  END IF;

  -- Try session org first
  BEGIN
    v_org := current_organization_uuid();
  EXCEPTION WHEN OTHERS THEN
    v_org := NULL;
  END;

  -- Infer org from reference if needed
  IF v_org IS NULL THEN
    IF v_ref_type = 'purchase' THEN
      SELECT organization_id INTO v_org
      FROM public.property_purchases
      WHERE id = v_ref_id AND deleted_at IS NULL
      LIMIT 1;
    ELSIF v_ref_type = 'rent_invoice' THEN
      SELECT organization_id INTO v_org
      FROM public.rent_invoices
      WHERE id = v_ref_id AND deleted_at IS NULL
      LIMIT 1;
    END IF;
  END IF;

  -- Last fallback: payment.property_id -> properties.organization_id
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
    RAISE EXCEPTION
      'Cannot infer organization_id for payment %. Set app.organization_id or ensure reference tables have org.',
      p_payment_id;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.payment_splits ps WHERE ps.payment_id = p_payment_id) THEN
    RAISE EXCEPTION
      'No payment_splits for payment %. Run ensure_payment_splits() before crediting.',
      p_payment_id;
  END IF;

  -- Reference mapping (important for your unique indexes)
  IF v_ref_type = 'purchase' THEN
    v_ins_ref_type := 'purchase';
    v_ins_ref_id   := v_ref_id;
  ELSIF v_ref_type = 'rent_invoice' THEN
    v_ins_ref_type := 'rent_invoice';
    v_ins_ref_id   := v_ref_id;
  ELSE
    v_ins_ref_type := 'payment';
    v_ins_ref_id   := p_payment_id;
  END IF;

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

    -- ✅ PURCHASE ESCROW RULE:
    -- If purchase: do NOT credit seller OR platform at payment time.
    -- Put BOTH payee + platform_fee into escrow. Release handles platform fee later.
    IF v_ref_type = 'purchase'
       AND (s.split_type = 'payee'::public.split_type OR s.split_type = 'platform_fee'::public.split_type) THEN

      v_wallet := public.get_or_create_org_escrow_wallet(v_org, s.currency::text);
      v_txn := 'credit_escrow'::public.wallet_transaction_type;

    ELSE
      v_wallet := public.ensure_wallet_account(v_org, v_kind, v_user, s.currency::text);

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
      v_txn,
      v_ins_ref_type,
      v_ins_ref_id,
      s.amount,
      s.currency,
      CASE
        WHEN v_ref_type = 'purchase'
             AND (s.split_type = 'payee'::public.split_type OR s.split_type = 'platform_fee'::public.split_type)
          THEN 'Escrow credit from payment ' || p_payment_id::text || ' (purchase ' || v_ref_id::text || ')'
        ELSE
          'Credit from payment ' || p_payment_id::text || ' (' || s.split_type::text || ')'
      END
    )
    ON CONFLICT DO NOTHING;
  END LOOP;
END;
$function$;

COMMIT;
SQL

echo "✅ Patched wallet_credit_from_splits() purchase behavior."