#!/usr/bin/env bash
set -Eeuo pipefail
trap 'echo "❌ Failed at line $LINENO: $BASH_COMMAND" >&2' ERR

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== Fix/Verify invoice payment flow =="

# Defaults
export API="${API:-http://127.0.0.1:4000}"
export DB_NAME="${DB_NAME:-rentease}"

echo "API=$API"
echo "DB_NAME=$DB_NAME"

# Check server
if ! curl -sS "$API/v1/db/ping" >/dev/null 2>&1; then
  echo "❌ Server not reachable at $API"
  echo "➡️ Run: npm run dev"
  exit 1
fi

# Login -> TOKEN
if [ ! -f "./scripts/login.sh" ]; then
  echo "❌ scripts/login.sh not found"
  exit 1
fi

eval "$(./scripts/login.sh)"
if [ -z "${TOKEN:-}" ]; then
  echo "❌ TOKEN not set after login.sh"
  exit 1
fi

# ORG_ID
ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
if [ -z "${ORG_ID:-}" ] || [ "$ORG_ID" = "null" ]; then
  echo "❌ Could not fetch ORG_ID from /v1/me"
  exit 1
fi
export ORG_ID

echo "ORG_ID=$ORG_ID"

# Latest invoice
INVOICE_ID="$(psql -d "$DB_NAME" -Atc "select id from public.rent_invoices where deleted_at is null order by created_at desc limit 1;")"
if [ -z "${INVOICE_ID:-}" ]; then
  echo "❌ No rent_invoices found in DB."
  echo "➡️ Generate one first via /v1/tenancies/:id/rent-invoices/generate"
  exit 1
fi
export INVOICE_ID

echo "INVOICE_ID=$INVOICE_ID"

echo "---- BEFORE"
psql -d "$DB_NAME" -c "select invoice_number, status, total_amount, paid_amount, paid_at from public.rent_invoices where id='$INVOICE_ID';"

echo "---- PAY"
curl -sS -X POST "$API/v1/rent-invoices/$INVOICE_ID/pay" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d '{"paymentMethod":"card"}' | jq

echo "---- AFTER"
psql -d "$DB_NAME" -c "select invoice_number, status, total_amount, paid_amount, paid_at from public.rent_invoices where id='$INVOICE_ID';"

echo "✅ Done."
