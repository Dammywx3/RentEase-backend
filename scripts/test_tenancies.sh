#!/usr/bin/env bash
set -euo pipefail

API="${API:-http://127.0.0.1:4000}"
DB_NAME="${DB_NAME:-rentease}"

eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

ME_ID="$(curl -s $API/v1/me -H "authorization: Bearer $TOKEN" | jq -r ".data.id")"
ORG_ID="$(curl -s $API/v1/me -H "authorization: Bearer $TOKEN" | jq -r ".data.organization_id // .data.organizationId")"
PROPERTY_ID="$(curl -s "$API/v1/properties?limit=1&offset=0" -H "authorization: Bearer $TOKEN" -H "x-organization-id: $ORG_ID" | jq -r ".data[0].id")"
LISTING_ID="$(curl -s "$API/v1/listings?limit=1&offset=0" -H "authorization: Bearer $TOKEN" -H "x-organization-id: $ORG_ID" | jq -r ".data[0].id")"

echo "ME_ID=$ME_ID"
echo "ORG_ID=$ORG_ID"
echo "PROPERTY_ID=$PROPERTY_ID"
echo "LISTING_ID=$LISTING_ID"

BODY=$(cat <<JSON
{
  "listingId":"$LISTING_ID",
  "propertyId":"$PROPERTY_ID",
  "tenantId":"$ME_ID",
  "startDate":"2026-02-01",
  "nextDueDate":"2026-03-01",
  "rentAmount":2000,
  "securityDeposit":500,
  "status":"pending_start"
}
JSON
)

echo
echo "POST #1 (should create or reuse)..."
R1=$(curl -s -X POST "$API/v1/tenancies" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d "$BODY")
echo "$R1" | jq
ID1=$(echo "$R1" | jq -r ".data.id")

echo
echo "POST #2 (should NOT 23505; should reuse and return same open tenancy)..."
R2=$(curl -s -X POST "$API/v1/tenancies" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d "$BODY")
echo "$R2" | jq
ID2=$(echo "$R2" | jq -r ".data.id")

echo
if [ "$ID1" = "$ID2" ]; then
  echo "✅ Idempotent: same tenancy returned on repeat POST (id=$ID2)"
else
  echo "⚠️ Different IDs returned (unexpected): $ID1 vs $ID2"
fi

echo
echo "Listing tenancies (API)..."
curl -s "$API/v1/tenancies?limit=10&offset=0" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" | jq

echo
echo "DB check: open tenancies for this tenant+property (deleted_at IS NULL only)"
PAGER=cat psql -d "$DB_NAME" -c "
select id, status, deleted_at, created_at
from public.tenancies
where tenant_id = '$ME_ID'
  and property_id = '$PROPERTY_ID'
  and deleted_at is null
  and status in ('active','pending_start')
order by created_at desc;
"
