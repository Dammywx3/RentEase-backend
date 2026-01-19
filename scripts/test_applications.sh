#!/usr/bin/env bash
set -euo pipefail

API="http://127.0.0.1:4000"
APP_PATH="/v1/applications"
LIST_PATH="/v1/applications"

# 1) Login (sets TOKEN)
eval "$(./scripts/login.sh)"
echo "✅ TOKEN set"

# 2) Quick health check
curl -s "$API/v1/health" | jq >/dev/null || true

# 3) Me + org
ME_ID="$(curl -s "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"
ORG_ID="$(curl -s "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
echo "ME_ID=$ME_ID"
echo "ORG_ID=$ORG_ID"

# 4) Pick a property (latest)
PROPERTY_ID="$(curl -s "$API/v1/properties?limit=1&offset=0" \
  -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"
echo "PROPERTY_ID=$PROPERTY_ID"

# 5) Pick a listing (latest)
LISTING_ID="$(curl -s "$API/v1/listings?limit=1&offset=0" \
  -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"
echo "LISTING_ID=$LISTING_ID"

# 6) Create application
echo
echo "Creating application..."
CREATE_RES="$(
  curl -s -X POST "$API$APP_PATH" \
    -H "content-type: application/json" \
    -H "authorization: Bearer $TOKEN" \
    -d "{
      \"listingId\":\"$LISTING_ID\",
      \"propertyId\":\"$PROPERTY_ID\",
      \"message\":\"I want to rent this place.\",
      \"monthlyIncome\":4000,
      \"moveInDate\":\"2026-02-01\"
    }"
)"
echo "$CREATE_RES" | jq
APPLICATION_ID="$(echo "$CREATE_RES" | jq -r '.data.id // empty')"
echo "APPLICATION_ID=${APPLICATION_ID:-"(not returned)"}"

# 7) List applications
echo
echo "Listing applications..."
curl -s "$API$LIST_PATH?limit=10&offset=0" \
  -H "authorization: Bearer $TOKEN" | jq

# 8) DB check
echo
echo "DB check: rental_applications (last 5)"
PAGER=cat psql -d rentease -c "select id, listing_id, property_id, applicant_id, status, monthly_income, move_in_date, created_at from rental_applications order by created_at desc limit 5;"
