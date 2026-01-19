#!/usr/bin/env bash
set -euo pipefail

eval "$(./scripts/login.sh)" >/dev/null

echo "✅ TOKEN set"

PROPERTY_ID="$(curl -s "http://127.0.0.1:4000/v1/properties?limit=1&offset=0" \
  -H "authorization: Bearer $TOKEN" | jq -r '.data[0].id')"

ME_ID="$(curl -s http://127.0.0.1:4000/v1/me -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"

echo "PROPERTY_ID=$PROPERTY_ID"
echo "ME_ID=$ME_ID"

curl -s -X POST http://127.0.0.1:4000/v1/listings \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -d "{
    \"propertyId\":\"$PROPERTY_ID\",
    \"kind\":\"agent_direct\",
    \"agentId\":\"$ME_ID\",
    \"payeeUserId\":\"$ME_ID\",
    \"basePrice\":1500,
    \"listedPrice\":1600,
    \"isPublic\": true
  }" | jq

echo
echo "DB check:"
psql -d rentease -c "select id, status, created_by, agent_id, payee_user_id from property_listings order by created_at desc limit 3;"
