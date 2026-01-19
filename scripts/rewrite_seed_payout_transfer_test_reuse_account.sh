#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/seed_payout_account_create_payout_and_test_transfer.sh"
ts=$(date +%s)

cp "$FILE" "${FILE}.bak.${ts}" 2>/dev/null || true
echo "Backup: ${FILE}.bak.${ts}"

cat > "$FILE" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgres://localhost:5432/rentease}"

# Ensure PAYSTACK env is loaded for signature calc (optional; webhook route will verify)
if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "=== Picking ORG/USER/WALLET IDs ==="
ORG_ID="$(psql "$DB_URL" -qAtX -P pager=off -v ON_ERROR_STOP=1 -c "select id::text from public.organizations order by created_at asc limit 1;")"
USER_ID="$(psql "$DB_URL" -qAtX -P pager=off -v ON_ERROR_STOP=1 -c "select id::text from public.users order by created_at asc limit 1;")"
WALLET_ID="$(psql "$DB_URL" -qAtX -P pager=off -v ON_ERROR_STOP=1 -c "select id::text from public.wallet_accounts where user_id='$USER_ID'::uuid order by created_at asc limit 1;")"

if [[ -z "$ORG_ID" || -z "$USER_ID" || -z "$WALLET_ID" ]]; then
  echo "ERROR: missing required seed data."
  echo "ORG_ID=$ORG_ID"
  echo "USER_ID=$USER_ID"
  echo "WALLET_ID=$WALLET_ID"
  exit 1
fi

echo "ORG_ID=$ORG_ID"
echo "USER_ID=$USER_ID"
echo "WALLET_ID=$WALLET_ID"
echo

echo "=== payout_accounts columns ==="
psql "$DB_URL" -P pager=off -c "\d public.payout_accounts" \
  | awk -F'|' 'NR>3 && $1 ~ /^[[:space:]]*[a-z_]/ {gsub(/[[:space:]]/,"",$1); print $1}' \
  | tr '\n' ' '
echo
echo

# Reuse or create payout_account (unique: user_id, provider, provider_token)
PROVIDER="paystack"
PROVIDER_TOKEN="TEST_PROVIDER_TOKEN"
CURRENCY="NGN"
LABEL="Test Payout Account"

echo "=== Ensure payout_account exists (reuse if already inserted) ==="
PAYOUT_ACCT_ID="$(psql "$DB_URL" -qAtX -P pager=off -v ON_ERROR_STOP=1 -c "
select id::text
from public.payout_accounts
where user_id = '$USER_ID'::uuid
  and provider = '$PROVIDER'
  and provider_token = '$PROVIDER_TOKEN'
limit 1;
")"

if [[ -z "$PAYOUT_ACCT_ID" ]]; then
  PAYOUT_ACCT_ID="$(psql "$DB_URL" -qAtX -P pager=off -v ON_ERROR_STOP=1 -c "
insert into public.payout_accounts (organization_id, user_id, currency, provider, provider_token, label)
values ('$ORG_ID'::uuid, '$USER_ID'::uuid, '$CURRENCY', '$PROVIDER', '$PROVIDER_TOKEN', '$LABEL')
returning id::text;
")"
  echo "✅ Created PAYOUT_ACCT_ID=$PAYOUT_ACCT_ID"
else
  echo "✅ Reusing PAYOUT_ACCT_ID=$PAYOUT_ACCT_ID"
fi
echo

# Create payout
echo "=== Create payout ==="
AMOUNT="1000.00"

PAYOUT_ID="$(psql "$DB_URL" -qAtX -P pager=off -v ON_ERROR_STOP=1 -c "
insert into public.payouts (organization_id, user_id, wallet_account_id, payout_account_id, amount, currency, status)
values ('$ORG_ID'::uuid, '$USER_ID'::uuid, '$WALLET_ID'::uuid, '$PAYOUT_ACCT_ID'::uuid, $AMOUNT::numeric, '$CURRENCY', 'pending'::public.payout_status)
returning id::text;
")"
echo "✅ PAYOUT_ID=$PAYOUT_ID"
echo

# Set gateway_payout_id so finalize can match by transfer_code too
TRANSFER_CODE="trf_test_${PAYOUT_ID:0:8}"
psql "$DB_URL" -qAtX -P pager=off -v ON_ERROR_STOP=1 -c "
update public.payouts
set gateway_payout_id = '$TRANSFER_CODE',
    updated_at = now()
where id = '$PAYOUT_ID'::uuid;
" >/dev/null

echo "=== Sending transfer.success webhook ==="
REF="payout_${PAYOUT_ID}"
BODY="{\"event\":\"transfer.success\",\"data\":{\"id\":\"trf_test_123\",\"transfer_code\":\"$TRANSFER_CODE\",\"reference\":\"$REF\",\"status\":\"success\"}}"

# If no PAYSTACK_SECRET_KEY, still send (server may be running with env already)
SIG=""
if [[ -n "${PAYSTACK_SECRET_KEY:-}" ]]; then
  SIG="$(printf '%s' "$BODY" | openssl dgst -sha512 -mac HMAC -macopt "key:$PAYSTACK_SECRET_KEY" | awk '{print $NF}')"
fi

if [[ -n "$SIG" ]]; then
  curl -i -X POST "http://127.0.0.1:4000/webhooks/paystack" \
    -H "Content-Type: application/json" \
    -H "x-paystack-signature: $SIG" \
    --data "$BODY"
else
  echo "WARN: PAYSTACK_SECRET_KEY not set in this shell; sending without signature header."
  curl -i -X POST "http://127.0.0.1:4000/webhooks/paystack" \
    -H "Content-Type: application/json" \
    --data "$BODY"
fi

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
where id = '$PAYOUT_ID'::uuid;
"
SCRIPT

chmod +x "$FILE"
echo "✅ Rewrote: $FILE"
echo "Run: bash $FILE"
