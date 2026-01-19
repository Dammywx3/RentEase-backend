#!/usr/bin/env bash
set -u

# If sourced, we must NOT exit the user's shell.
_sourced=0
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _sourced=1
fi

die() {
  echo "❌ $*" >&2
  if [ "$_sourced" -eq 1 ]; then
    return 1
  else
    exit 1
  fi
}

BASE="${BASE:-http://127.0.0.1:4000}"
DEV_EMAIL="${DEV_EMAIL:-dev_1768638237@rentease.local}"
DEV_PASS="${DEV_PASS:-Passw0rd!234}"

echo "============================================================"
echo "RentEase RLS Smoke Test"
echo "BASE=$BASE"
echo "DEV_EMAIL=$DEV_EMAIL"
echo "============================================================"

LOGIN_JSON="$(curl -s -X POST "$BASE/v1/auth/login" \
  -H "content-type: application/json" \
  -d "{\"email\":\"$DEV_EMAIL\",\"password\":\"$DEV_PASS\"}")"

TOKEN="$(python3 - <<PY
import json
j=json.loads("""$LOGIN_JSON""")
print(j.get("token",""))
PY
)"

ORG="$(python3 - <<PY
import json
j=json.loads("""$LOGIN_JSON""")
print((j.get("user") or {}).get("organization_id",""))
PY
)"

USER_ID="$(python3 - <<PY
import json
j=json.loads("""$LOGIN_JSON""")
print((j.get("user") or {}).get("id",""))
PY
)"

[ -n "$TOKEN" ] || die "Login failed (no token). Response: $LOGIN_JSON"
[ -n "$ORG" ] || die "Login failed (no organization_id). Response: $LOGIN_JSON"
[ -n "$USER_ID" ] || die "Login failed (no user id). Response: $LOGIN_JSON"

export TOKEN ORG USER_ID

echo "✅ Logged in"
echo "TOKEN_LEN=${#TOKEN}"
echo "ORG=$ORG"
echo "USER_ID=$USER_ID"
echo ""

hit () {
  local method="$1"
  local path="$2"
  local data="${3:-}"
  local url="$BASE$path"

  echo "------------------------------------------------------------"
  echo "$method $path"

  if [ "$method" = "GET" ]; then
    curl -s -i \
      -H "Authorization: Bearer $TOKEN" \
      -H "x-organization-id: $ORG" \
      "$url" || true
  else
    curl -s -i \
      -H "Authorization: Bearer $TOKEN" \
      -H "x-organization-id: $ORG" \
      -H "content-type: application/json" \
      -X "$method" \
      -d "$data" \
      "$url" || true
  fi
  echo ""
}

hit GET "/debug/pgctx"
hit GET "/v1/me"
hit GET "/v1/organizations/$ORG"
hit GET "/v1/listings?limit=1&offset=0"
hit GET "/v1/applications?limit=1&offset=0"
hit GET "/v1/viewings?limit=1&offset=0"
hit GET "/v1/tenancies?limit=1&offset=0"
hit GET "/v1/rent-invoices?limit=1&offset=0"
hit GET "/v1/purchases?limit=1&offset=0"

echo "============================================================"
echo "✅ Smoke test finished."
echo "============================================================"
