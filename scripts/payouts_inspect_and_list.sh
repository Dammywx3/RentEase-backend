#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DATABASE_URL:-postgres://localhost:5432/rentease}"

echo "=== payouts table columns ==="
psql "$DB_URL" -P pager=off -c "\d public.payouts"

echo
echo "=== last 10 payouts (safe select) ==="
psql "$DB_URL" -P pager=off -c "
select
  id,
  organization_id,
  status,
  gateway_payout_id,
  amount,
  currency,
  created_at
from public.payouts
order by created_at desc
limit 10;
"
