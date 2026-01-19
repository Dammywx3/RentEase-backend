#!/usr/bin/env bash
set -o pipefail

DB_NAME="${DB_NAME:-rentease}"
FILE="src/services/purchase_payments.service.ts"

echo "DB_NAME=$DB_NAME"
echo "PWD=$(pwd)"
echo ""

# ---------- (A) Schema fix: add purchase unique index for wallet txns ----------
echo "== (A) Ensuring wallet tx unique index for reference_type='purchase' =="

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
echo "== (B) Patching purchase service to use referenceType='purchase' =="

# Safety backup
mkdir -p scripts/.bak src/services
if [ -f "$FILE" ]; then
  ts="$(date +%Y%m%d_%H%M%S)"
  cp "$FILE" "scripts/.bak/purchase_payments.service.ts.bak.$ts"
  echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.$ts"
else
  echo "⚠️ $FILE not found (skipping patch). Make sure purchase_payments.service.ts exists."
  echo ""
  echo "✅ DONE (schema fixed)."
  exit 0
fi

# Patch: ensure ledger referenceType uses 'purchase'
# (This is safe even if it's already correct.)
perl -0777 -i -pe "s/referenceType:\s*'rent_invoice'/referenceType: 'purchase'/g" "$FILE"
perl -0777 -i -pe "s/referenceType:\s*\"rent_invoice\"/referenceType: \"purchase\"/g" "$FILE"

# Patch: if you used 'purchase' already but with another string like 'property_purchase', normalize it.
perl -0777 -i -pe "s/referenceType:\s*'property_purchase'/referenceType: 'purchase'/g" "$FILE"
perl -0777 -i -pe "s/referenceType:\s*\"property_purchase\"/referenceType: \"purchase\"/g" "$FILE"

echo "✅ PATCHED: $FILE"
echo ""

echo "== (C) Quick schema visibility checks (optional) =="
echo "---- wallet_transactions unique indexes"
PAGER=cat psql -d "$DB_NAME" -c "
select indexname
from pg_indexes
where schemaname='public' and tablename='wallet_transactions'
order by indexname;
" || true

echo ""
echo "---- purchase tables exist?"
PAGER=cat psql -d "$DB_NAME" -c "
select table_name
from information_schema.tables
where table_schema='public'
  and table_name in ('property_purchases','property_purchase_payments','escrow_accounts','escrow_transactions','property_purchase_events')
order by table_name;
" || true

echo ""
echo "✅ DONE"
echo ""
echo "NEXT (after you wire the route + run a purchase payment):"
echo "1) export PURCHASE_ID=<uuid>"
echo "2) Verify ledger txns:"
echo "   PAGER=cat psql -d \"$DB_NAME\" -c \""
echo "   select wt.txn_type, wt.amount, wa.is_platform_wallet, wa.user_id"
echo "   from public.wallet_transactions wt"
echo "   join public.wallet_accounts wa on wa.id = wt.wallet_account_id"
echo "   where wt.reference_type='purchase'"
echo "     and wt.reference_id='\${PURCHASE_ID}'::uuid"
echo "   order by wt.created_at asc;\""
echo ""
echo "You should see 2 rows:"
echo "  - credit_platform_fee (platform wallet)"
echo "  - credit_payee        (seller wallet)"
