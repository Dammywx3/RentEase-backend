#!/usr/bin/env bash
set -eo pipefail
DB_NAME="${DB_NAME:-rentease}"

echo "DB_NAME=$DB_NAME"

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

-- Verify it exists
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND indexname='uniq_wallet_tx_purchase_credit';
SQL

echo ""
echo "✅ DONE"
echo "➡️ After you run a purchase payment, verify txns:"
echo "   PAGER=cat psql -d \"$DB_NAME\" -c \"select wt.txn_type, wt.amount, wa.is_platform_wallet, wa.user_id from public.wallet_transactions wt join public.wallet_accounts wa on wa.id=wt.wallet_account_id where wt.reference_type='purchase' and wt.reference_id='<PURCHASE_ID>'::uuid order by wt.created_at asc;\""
