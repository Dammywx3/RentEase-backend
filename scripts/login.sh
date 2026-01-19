#!/usr/bin/env bash
set -euo pipefail

EMAIL="${EMAIL:-test@rentease.local}"
PASSWORD="${PASSWORD:-Password123!}"

# Support both BASE_URL and API as env var names
BASE_URL="${BASE_URL:-${API:-http://127.0.0.1:4000}}"

# 1) Login -> TOKEN
TOKEN="$(
  curl -sS -X POST "$BASE_URL/v1/auth/login" \
    -H "content-type: application/json" \
    -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  | jq -r '.token'
)"

if [[ -z "${TOKEN:-}" || "$TOKEN" == "null" ]]; then
  echo "Login failed: token missing" >&2
  exit 1
fi

# 2) /v1/me -> ORG_ID + ME_ID
ME_JSON="$(
  curl -sS "$BASE_URL/v1/me" \
    -H "authorization: Bearer $TOKEN"
)"

ME_ID="$(echo "$ME_JSON" | jq -r '.data.id // empty')"
ORG_ID="$(echo "$ME_JSON" | jq -r '.data.organization_id // .data.organizationId // empty')"

if [[ -z "${ME_ID:-}" || -z "${ORG_ID:-}" ]]; then
  echo "Login ok, but /v1/me missing ids. Response:" >&2
  echo "$ME_JSON" >&2
  exit 1
fi

# IMPORTANT: only print export lines for eval
echo "export API=\"$BASE_URL\""
echo "export BASE_URL=\"$BASE_URL\""
echo "export TOKEN=\"$TOKEN\""
echo "export ME_ID=\"$ME_ID\""
echo "export ORG_ID=\"$ORG_ID\""