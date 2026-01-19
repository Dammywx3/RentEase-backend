#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DATABASE_URL:-postgres://localhost:5432/rentease}"

# load env for PAYSTACK_SECRET_KEY
if [[ -f ".env" ]]; then
  set -a
  source .env
  set +a
fi

if [[ -z "${PAYSTACK_SECRET_KEY:-}" ]]; then
  echo "ERROR: PAYSTACK_SECRET_KEY not set. Put it in .env and rerun."
  exit 1
fi

echo "=== picking IDs for payout insert ==="
ORG_ID="$(psql "$DB_URL" -P pager=off -t -A -c "select id::text from public.organizations limit 1;")"
USER_ID="$(psql "$DB_URL" -P pager=off -t -A -c "select id::text from public.users limit 1;")"
WALLET_ID="$(psql "$DB_URL" -P pager=off -t -A -c "select id::text from public.wallet_accounts limit 1;")"
PAYOUT_ACCT_ID="$(psql "$DB_URL" -P pager=off -t -A -c "select id::text from public.payout_accounts limit 1;")"

if [[ -z "$ORG_ID" || -z "$USER_ID" || -z "$WALLET_ID" || -z "$PAYOUT_ACCT_ID" ]]; then
  echo "ERROR: missing required seed data."
  echo "ORG_ID=$ORG_ID"
  echo "USER_ID=$USER_ID"
  echo "WALLET_ID=$WALLET_ID"
  echo "PAYOUT_ACCT_ID=$PAYOUT_ACCT_ID"
  echo
  echo "Fix: create at least 1 org, user, wallet_account, payout_account first."
  exit 1
fi

echo "ORG_ID=$ORG_ID"
echo "USER_ID=$USER_ID"
echo "WALLET_ID=$WALLET_ID"
echo "PAYOUT_ACCT_ID=$PAYOUT_ACCT_ID"
echo

echo "=== inserting payout ==="
PAYOUT_ID="$(psql "$DB_URL" -P pager=off -t -A -c "
insert into public.payouts (
  organization_id, user_id, wallet_account_id, payout_account_id, amount, currency, status
) values (
  '$ORG_ID'::uuid,
  '$USER_ID'::uuid,
  '$WALLET_ID'::uuid,
  '$PAYOUT_ACCT_ID'::uuid,
  1000.00,
  'NGN',
  'pending'::payout_status
)
returning id::text;
")"

echo "✅ PAYOUT_ID=$PAYOUT_ID"
echo

REF="payout_${PAYOUT_ID}"
TRANSFER_CODE="$REF"

BODY=$(cat <<JSON
{"event":"transfer.success","data":{"reference":"$REF","transfer_code":"$TRANSFER_CODE","amount":100000,"currency":"NGN","status":"success"}}
JSON
)

SIG=$(printf '%s' "$BODY" \
  | openssl dgst -sha512 -mac HMAC -macopt "key:$PAYSTACK_SECRET_KEY" \
  | awk '{print $NF}')

echo "=== sending transfer.success webhook ==="
curl -i -X POST "http://127.0.0.1:4000/webhooks/paystack" \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: $SIG" \
  --data "$BODY"

echo
echo "=== payout after webhook ==="
psql "$DB_URL" -P pager=off -c "
select
  id,
  status,
  gateway_payout_id,
  processed_at,
  requested_at,
  updated_at
from public.payouts
where id = '$PAYOUT_ID'::uuid;
"
