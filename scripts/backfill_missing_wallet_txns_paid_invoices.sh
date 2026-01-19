#!/usr/bin/env bash
set -euo pipefail

DB_NAME="${DB_NAME:-rentease}"

if [[ -z "${ORG_ID:-}" ]]; then
  echo "❌ ORG_ID is required. Example:"
  echo "   export ORG_ID=\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r '.data.organization_id')"
  exit 1
fi

echo "DB_NAME=$DB_NAME"
echo "ORG_ID=$ORG_ID"
echo ""

psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<SQL
\\echo '== PREVIEW: paid invoices with NO wallet txns (reference_type=rent_invoice) =='
SELECT
  ri.id AS invoice_id,
  ri.invoice_number,
  ri.total_amount,
  ri.currency,
  ri.paid_at,
  p.owner_id AS payee_user_id
FROM public.rent_invoices ri
JOIN public.properties p ON p.id = ri.property_id
WHERE ri.organization_id = '$ORG_ID'::uuid
  AND ri.deleted_at IS NULL
  AND ri.status = 'paid'::invoice_status
  AND NOT EXISTS (
    SELECT 1
    FROM public.wallet_transactions wt
    WHERE wt.reference_type='rent_invoice'
      AND wt.reference_id = ri.id
  )
ORDER BY ri.created_at ASC;

\\echo ''
\\echo '== APPLY: insert missing ledger txns for those invoices =='

DO \$\$
DECLARE
  r RECORD;
  v_currency text;
  v_platform_wallet_id uuid;
  v_payee_wallet_id uuid;
  v_fee numeric(15,2);
  v_net numeric(15,2);
BEGIN
  FOR r IN
    SELECT
      ri.id AS invoice_id,
      ri.organization_id,
      ri.invoice_number,
      ri.total_amount::numeric AS total_amount,
      COALESCE(ri.currency,'USD') AS currency,
      p.owner_id AS payee_user_id
    FROM public.rent_invoices ri
    JOIN public.properties p ON p.id = ri.property_id
    WHERE ri.organization_id = '$ORG_ID'::uuid
      AND ri.deleted_at IS NULL
      AND ri.status = 'paid'::invoice_status
      AND NOT EXISTS (
        SELECT 1
        FROM public.wallet_transactions wt
        WHERE wt.reference_type='rent_invoice'
          AND wt.reference_id = ri.id
      )
    ORDER BY ri.created_at ASC
  LOOP
    v_currency := r.currency;

    -- Fee split (2.5%)
    v_fee := round((r.total_amount * 2.5 / 100.0)::numeric, 2);
    IF v_fee < 0 THEN v_fee := 0; END IF;

    v_net := round((r.total_amount - v_fee)::numeric, 2);
    IF v_net < 0 THEN v_net := 0; END IF;

    -- Pick oldest platform wallet for this org+currency
    SELECT wa.id
    INTO v_platform_wallet_id
    FROM public.wallet_accounts wa
    WHERE wa.organization_id = r.organization_id
      AND wa.is_platform_wallet = true
      AND wa.currency = v_currency
    ORDER BY wa.created_at ASC
    LIMIT 1;

    IF v_platform_wallet_id IS NULL THEN
      RAISE EXCEPTION 'No platform wallet found for org % currency %', r.organization_id, v_currency;
    END IF;

    -- Ensure payee wallet exists (org+payee+currency)
    SELECT wa.id
    INTO v_payee_wallet_id
    FROM public.wallet_accounts wa
    WHERE wa.organization_id = r.organization_id
      AND wa.user_id = r.payee_user_id
      AND wa.is_platform_wallet = false
      AND wa.currency = v_currency
    ORDER BY wa.created_at ASC
    LIMIT 1;

    IF v_payee_wallet_id IS NULL THEN
      INSERT INTO public.wallet_accounts (organization_id, user_id, currency, is_platform_wallet)
      VALUES (r.organization_id, r.payee_user_id, v_currency, false)
      RETURNING id INTO v_payee_wallet_id;
    END IF;

    -- 1) Credit payee NET (only if missing)
    INSERT INTO public.wallet_transactions (
      organization_id, wallet_account_id, txn_type,
      reference_type, reference_id, amount, currency, note
    )
    SELECT
      r.organization_id, v_payee_wallet_id, 'credit_payee'::wallet_transaction_type,
      'rent_invoice', r.invoice_id, v_net, v_currency,
      format('Backfill payee net for invoice %s', COALESCE(r.invoice_number::text, r.invoice_id::text))
    WHERE v_net > 0
      AND NOT EXISTS (
        SELECT 1 FROM public.wallet_transactions wt
        WHERE wt.reference_type='rent_invoice'
          AND wt.reference_id=r.invoice_id
          AND wt.txn_type='credit_payee'::wallet_transaction_type
      );

    -- 2) Credit platform fee (only if missing)
    INSERT INTO public.wallet_transactions (
      organization_id, wallet_account_id, txn_type,
      reference_type, reference_id, amount, currency, note
    )
    SELECT
      r.organization_id, v_platform_wallet_id, 'credit_platform_fee'::wallet_transaction_type,
      'rent_invoice', r.invoice_id, v_fee, v_currency,
      format('Backfill platform fee (2.5%%) for invoice %s', COALESCE(r.invoice_number::text, r.invoice_id::text))
    WHERE v_fee > 0
      AND NOT EXISTS (
        SELECT 1 FROM public.wallet_transactions wt
        WHERE wt.reference_type='rent_invoice'
          AND wt.reference_id=r.invoice_id
          AND wt.txn_type='credit_platform_fee'::wallet_transaction_type
      );

    RAISE NOTICE 'Backfilled invoice %: fee=%, net=% (currency=%)', r.invoice_id, v_fee, v_net, v_currency;
  END LOOP;
END
\$\$;

\\echo ''
\\echo '== AFTER: totals in PLATFORM wallets by txn_type (should be fee-only) =='
SELECT wt.txn_type,
       count(*) AS cnt,
       COALESCE(sum(wt.amount),0) AS total
FROM public.wallet_transactions wt
JOIN public.wallet_accounts wa ON wa.id = wt.wallet_account_id
WHERE wa.organization_id='$ORG_ID'::uuid
  AND wa.is_platform_wallet=true
GROUP BY wt.txn_type
ORDER BY wt.txn_type;

\\echo ''
\\echo '== AFTER: sample of backfilled invoices =='
SELECT
  ri.invoice_number,
  ri.id AS invoice_id,
  wt.txn_type,
  wt.amount,
  wa.is_platform_wallet,
  wa.user_id
FROM public.rent_invoices ri
JOIN public.wallet_transactions wt
  ON wt.reference_type='rent_invoice' AND wt.reference_id=ri.id
JOIN public.wallet_accounts wa
  ON wa.id=wt.wallet_account_id
WHERE ri.organization_id='$ORG_ID'::uuid
  AND ri.deleted_at IS NULL
  AND ri.status='paid'::invoice_status
ORDER BY ri.created_at DESC, wt.txn_type ASC
LIMIT 30;
SQL

echo ""
echo "✅ DONE"
echo "➡️ If you want to verify a specific invoice:"
echo "   export INVOICE_ID=<uuid>"
echo "   PAGER=cat psql -d \"$DB_NAME\" -c \"select wt.txn_type, wt.amount, wa.user_id, wa.is_platform_wallet from public.wallet_transactions wt join public.wallet_accounts wa on wa.id=wt.wallet_account_id where wt.reference_type='rent_invoice' and wt.reference_id='\$INVOICE_ID'::uuid order by wt.created_at asc;\""
