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
