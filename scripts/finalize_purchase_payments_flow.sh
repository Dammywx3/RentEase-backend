#!/usr/bin/env bash
set -o pipefail

DB_NAME="${DB_NAME:-rentease}"
SERVICE_FILE="src/services/purchase_payments.service.ts"

echo "DB_NAME=$DB_NAME"
echo ""

# -------------------------------
# (A) SCHEMA: unique index to prevent duplicate purchase ledger credits
# -------------------------------
echo "== (A) Ensure wallet tx uniqueness for purchase reference =="

PAGER=cat psql -d "$DB_NAME" -v ON_ERROR_STOP=1 <<'SQL'
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname='public'
      AND indexname='uniq_wallet_tx_purchase_credit'
  ) THEN
    EXECUTE $q$
      CREATE UNIQUE INDEX uniq_wallet_tx_purchase_credit
      ON public.wallet_transactions (wallet_account_id, reference_type, reference_id, txn_type)
      WHERE reference_type = 'purchase'::text;
    $q$;
    RAISE NOTICE 'Created index: uniq_wallet_tx_purchase_credit';
  ELSE
    RAISE NOTICE 'Index already exists: uniq_wallet_tx_purchase_credit';
  END IF;
END $$;

SELECT indexname
FROM pg_indexes
WHERE schemaname='public'
  AND indexname IN (
    'uniq_wallet_tx_rent_invoice_credit',
    'uniq_wallet_tx_payment_credit',
    'uniq_wallet_tx_purchase_credit'
  )
ORDER BY 1;
SQL

echo ""
# -------------------------------
# (B) SERVICE PATCH: normalize reference_type to 'purchase'
# -------------------------------
echo "== (B) Patch purchase service to reference_type='purchase' =="

mkdir -p scripts/.bak

if [ -f "$SERVICE_FILE" ]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  cp "$SERVICE_FILE" "scripts/.bak/purchase_payments.service.ts.bak.$ts"
  echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.$ts"

  # Normalize any referenceType value to 'purchase'
  perl -0777 -i -pe "s/referenceType:\s*'rent_invoice'/referenceType: 'purchase'/g" "$SERVICE_FILE"
  perl -0777 -i -pe "s/referenceType:\s*\"rent_invoice\"/referenceType: \"purchase\"/g" "$SERVICE_FILE"
  perl -0777 -i -pe "s/referenceType:\s*'property_purchase'/referenceType: 'purchase'/g" "$SERVICE_FILE"
  perl -0777 -i -pe "s/referenceType:\s*\"property_purchase\"/referenceType: \"purchase\"/g" "$SERVICE_FILE"

  echo "✅ PATCHED: $SERVICE_FILE"
else
  echo "⚠️ Missing: $SERVICE_FILE"
  echo "   (skip patch; schema still fixed)"
fi

echo ""
# -------------------------------
# (C) Helper verify script
# -------------------------------
echo "== (C) Write verify script =="

cat > scripts/verify_purchase_ledger.sh <<'VERIFY'
#!/usr/bin/env bash
set -o pipefail

DB_NAME="${DB_NAME:-rentease}"

if [ -z "${PURCHASE_ID:-}" ]; then
  echo "❌ PURCHASE_ID is not set"
  echo "Run: export PURCHASE_ID=<uuid>"
  exit 0
fi

PAGER=cat psql -d "$DB_NAME" -c "
select wt.txn_type,
       wt.amount,
       wa.is_platform_wallet,
       wa.user_id,
       wt.created_at
from public.wallet_transactions wt
join public.wallet_accounts wa on wa.id = wt.wallet_account_id
where wt.reference_type='purchase'
  and wt.reference_id='${PURCHASE_ID}'::uuid
order by wt.created_at asc;
"
VERIFY

chmod +x scripts/verify_purchase_ledger.sh
echo "✅ WROTE: scripts/verify_purchase_ledger.sh"

echo ""
echo "✅ DONE"
echo ""
echo "NEXT:"
echo "  1) export PURCHASE_ID=<uuid>"
echo "  2) bash scripts/verify_purchase_ledger.sh"
echo ""
echo "Expected rows:"
echo "  - credit_platform_fee (platform wallet)"
echo "  - credit_payee        (seller wallet)"
