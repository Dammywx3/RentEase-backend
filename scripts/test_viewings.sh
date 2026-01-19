#!/usr/bin/env bash
set -euo pipefail

API="http://127.0.0.1:4000"

eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

ME_ID="$(curl -s $API/v1/me -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"
PROPERTY_ID="$(curl -s "$API/v1/properties?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"
LISTING_ID="$(curl -s "$API/v1/listings?limit=1&offset=0" -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"

echo "ME_ID=$ME_ID"
echo "PROPERTY_ID=$PROPERTY_ID"
echo "LISTING_ID=$LISTING_ID"

echo
echo "Creating viewing..."
curl -s -X POST "$API/v1/viewings" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -d "{
    \"listingId\":\"$LISTING_ID\",
    \"propertyId\":\"$PROPERTY_ID\",
    \"scheduledAt\":\"2026-02-05T10:00:00Z\",
    \"viewMode\":\"in_person\",
    \"notes\":\"First viewing\"
  }" | jq

echo
echo "Listing viewings..."
curl -s "$API/v1/viewings?limit=10&offset=0" \
  -H "authorization: Bearer $TOKEN" | jq

echo
echo "DB check: property_viewings (last 5)"
PAGER=cat psql -d rentease -c "select id, listing_id, tenant_id, scheduled_at, view_mode, status, created_at from property_viewings order by created_at desc limit 5;"
