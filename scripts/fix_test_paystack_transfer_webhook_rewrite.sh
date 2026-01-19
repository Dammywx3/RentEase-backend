#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/test_paystack_transfer_webhook.sh"
ts=$(date +%s)
if [[ -f "$FILE" ]]; then
  cp "$FILE" "${FILE}.bak.${ts}"
  echo "Backup: ${FILE}.bak.${ts}"
fi

cat > "$FILE" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

DB_URL="${DB_URL:-postgres://localhost:5432/rentease}"

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <PAYOUT_UUID>"
  exit 1
fi

PAYOUT_ID="$1"
REF="payout_${PAYOUT_ID}"

# Load .env if PAYSTACK_SECRET_KEY missing
if [[ -z "${PAYSTACK_SECRET_KEY:-}" && -f .env ]]; then
  set -a
  source .env
  set +a
fi

if [[ -z "${PAYSTACK_SECRET_KEY:-}" ]]; then
  echo "ERROR: PAYSTACK_SECRET_KEY missing (export it or put it in .env)"
  exit 1
fi

# ensure payout exists
exists=$(psql "$DB_URL" -P pager=off -Atc "select count(*) from public.payouts where id='${PAYOUT_ID}'::uuid;") || true
if [[ "${exists:-0}" = "0" ]]; then
  echo "ERROR: payout not found: $PAYOUT_ID"
  exit 1
fi

BODY="{\"event\":\"transfer.success\",\"data\":{\"id\":\"trf_test_123\",\"transfer_code\":\"trf_test_123\",\"reference\":\"${REF}\",\"status\":\"success\"}}"
SIG=$(printf '%s' "$BODY" | openssl dgst -sha512 -mac HMAC -macopt "key:$PAYSTACK_SECRET_KEY" | awk '{print $NF}')

echo "=== sending transfer.success ==="
echo "reference=$REF"
echo

curl -s -i -X POST "http://127.0.0.1:4000/webhooks/paystack" \
  -H "Content-Type: application/json" \
  -H "x-paystack-signature: $SIG" \
  --data "$BODY"

echo
echo "=== payout after ==="
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
echo "Run: bash $FILE <PAYOUT_UUID>"
