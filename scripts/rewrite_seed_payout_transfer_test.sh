#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/seed_payout_account_create_payout_and_test_transfer.sh"
ts=$(date +%s)
if [[ -f "$FILE" ]]; then
  cp "$FILE" "${FILE}.bak.${ts}"
  echo "Backup: ${FILE}.bak.${ts}"
fi

cat > "$FILE" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

DB_URL="${DB_URL:-postgres://localhost:5432/rentease}"

# Load .env so PAYSTACK_SECRET_KEY exists for signature
if [[ -f ".env" ]]; then
  set -a
  source .env
  set +a
fi

if [[ -z "${PAYSTACK_SECRET_KEY:-}" ]]; then
  echo "ERROR: PAYSTACK_SECRET_KEY not set. Ensure .env has it and re-run."
  exit 1
fi

echo "=== Picking ORG/USER/WALLET IDs ==="
ORG_ID="$(psql "$DB_URL" -P pager=off -Atc "select id::text from public.organizations order by created_at asc limit 1;")"
USER_ID="$(psql "$DB_URL" -P pager=off -Atc "select id::text from public.users order by created_at asc limit 1;")"
WALLET_ID="$(psql "$DB_URL" -P pager=off -Atc "select id::text from public.wallet_accounts order by created_at asc limit 1;")"

echo "ORG_ID=$ORG_ID"
echo "USER_ID=$USER_ID"
echo "WALLET_ID=$WALLET_ID"

if [[ -z "$ORG_ID" || -z "$USER_ID" || -z "$WALLET_ID" ]]; then
  echo "ERROR: missing required seed data (org/user/wallet_account)."
  exit 1
fi

echo
echo "=== Ensure payout_account exists ==="
# Create payout_account with required fields: user_id, provider, provider_token
PAYOUT_ACCT_ID="$(psql "$DB_URL" -P pager=off -Atc "
insert into public.payout_accounts (organization_id, user_id, provider, provider_token, currency, label, is_active)
values ('$ORG_ID'::uuid, '$USER_ID'::uuid, 'paystack', 'prov_tok_test_123', 'NGN', 'Test Payout Account', true)
returning id::text;
")"
echo "✅ PAYOUT_ACCT_ID=$PAYOUT_ACCT_ID"

echo
echo "=== Create payout ==="
PAYOUT_ID="$(psql "$DB_URL" -P pager=off -Atc "
insert into public.payouts (organization_id, user_id, wallet_account_id, payout_account_id, amount, currency, status)
values ('$ORG_ID'::uuid, '$USER_ID'::uuid, '$WALLET_ID'::uuid, '$PAYOUT_ACCT_ID'::uuid, 1000.00, 'NGN', 'pending')
returning id::text;
")"
echo "✅ PAYOUT_ID=$PAYOUT_ID"

# This is the key that finalizePaystackTransferEvent will match against
TRANSFER_CODE="trf_test_123"

echo
echo "=== Set payouts.gateway_payout_id ==="
psql "$DB_URL" -P pager=off -c "
update public.payouts
set gateway_payout_id='${TRANSFER_CODE}', updated_at=now()
where id='${PAYOUT_ID}'::uuid;
"

echo
echo "=== Sending transfer.success webhook ==="
REF="payout_${PAYOUT_ID}"

BODY="{\"event\":\"transfer.success\",\"data\":{\"id\":\"trf_event_001\",\"transfer_code\":\"${TRANSFER_CODE}\",\"reference\":\"${REF}\",\"status\":\"success\"}}"

SIG="$(printf '%s' "$BODY" \
  | openssl dgst -sha512 -mac HMAC -macopt "key:${PAYSTACK_SECRET_KEY}" \
  | awk '{print $NF}')"

curl -s -i -X POST "http://127.0.0.1:4000/webhooks/paystack" \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: ${SIG}" \
  --data "$BODY" | sed -n '1,18p'

echo
echo "=== Payout after webhook ==="
psql "$DB_URL" -P pager=off -c "
select
  id,
  status,
  gateway_payout_id,
  processed_at,
  requested_at,
  updated_at
from public.payouts
where id = '${PAYOUT_ID}'::uuid;
"
SCRIPT

chmod +x "$FILE"
echo "✅ Rewrote: $FILE"
echo "Run: bash $FILE"
