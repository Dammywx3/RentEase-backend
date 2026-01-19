#!/usr/bin/env bash
set -euo pipefail

# ensure login.sh set TOKEN
if [ -z "${TOKEN:-}" ]; then
  echo "ERROR: TOKEN not set. Run: export API=\"http://127.0.0.1:4000\"; eval \"\$(./scripts/login.sh)\""
  exit 1
fi

: "${DB_NAME:=rentease}"
: "${API:=http://127.0.0.1:4000}"

eval "$(./scripts/login.sh)"
ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"

echo "API=$API"
echo "ORG_ID=$ORG_ID"

INVOICE_ID="$(psql -d "$DB_NAME" -Atc "select id from public.rent_invoices where deleted_at is null order by created_at desc limit 1;")"
echo "INVOICE_ID=$INVOICE_ID"

echo "---- BEFORE"
psql -d "$DB_NAME" -c "select invoice_number,status,total_amount,paid_amount,paid_at from public.rent_invoices where id='$INVOICE_ID';" >/dev/null

echo "---- PAY (admin-only)"
curl -sS -X POST "$API/v1/rent-invoices/$INVOICE_ID/pay" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d '{"paymentMethod":"card"}' | jq

echo "---- AFTER"
psql -d "$DB_NAME" -c "select invoice_number,status,total_amount,paid_amount,paid_at from public.rent_invoices where id='$INVOICE_ID';"
