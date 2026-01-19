#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"
export API

echo "API=$API"

# login must set TOKEN
eval "$(./scripts/login.sh)"
if [ -z "${TOKEN:-}" ]; then
  echo "ERROR: TOKEN not set by scripts/login.sh"
  exit 1
fi

ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
ME_ROLE="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.role')"
echo "ORG_ID=$ORG_ID"
echo "ME_ROLE=$ME_ROLE"

TENANCY_ID="$(psql -d "$DB_NAME" -Atc "select id from public.tenancies where deleted_at is null order by created_at desc limit 1;")"
echo "TENANCY_ID=$TENANCY_ID"

# choose a new month you haven't used yet
GEN_PAYLOAD='{"periodStart":"2026-06-01","periodEnd":"2026-06-30","dueDate":"2026-07-01","subtotal":2000,"currency":"USD","notes":"June rent"}'

echo "---- GENERATE invoice"
GEN_RES="$(
  curl -sS -X POST "$API/v1/tenancies/$TENANCY_ID/rent-invoices/generate" \
    -H "content-type: application/json" \
    -H "authorization: Bearer $TOKEN" \
    -H "x-organization-id: $ORG_ID" \
    -d "$GEN_PAYLOAD"
)"

echo "$GEN_RES" | jq

OK="$(echo "$GEN_RES" | jq -r '.ok // false')"
if [ "$OK" != "true" ]; then
  echo "ERROR: generate failed (see JSON above)."
  exit 1
fi

NEW_INV_ID="$(echo "$GEN_RES" | jq -r '.data.id // empty')"
if [ -z "$NEW_INV_ID" ]; then
  echo "ERROR: generate returned ok:true but data.id missing."
  exit 1
fi

echo "NEW_INV_ID=$NEW_INV_ID"

echo "---- PAY #1"
curl -sS -X POST "$API/v1/rent-invoices/$NEW_INV_ID/pay" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d '{"paymentMethod":"card"}' | jq '{ok,alreadyPaid,status:.data.status,paid_at:.data.paid_at}'

echo "---- PAY #2"
curl -sS -X POST "$API/v1/rent-invoices/$NEW_INV_ID/pay" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d '{"paymentMethod":"card"}' | jq '{ok,alreadyPaid,status:.data.status,paid_at:.data.paid_at}'

echo "---- DB CHECK"
PAGER=cat psql -d "$DB_NAME" -c "select invoice_number,status,total_amount,paid_amount,paid_at from public.rent_invoices where id='$NEW_INV_ID';"

echo "✅ Done."
