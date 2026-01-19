#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"
DB="${DB:-rentease}"

EMAIL="${DEV_EMAIL:-${EMAIL:-}}"
PASSWORD="${DEV_PASS:-${PASSWORD:-}}"

PURCHASE_ID="${1:-}"
if [ -z "$PURCHASE_ID" ]; then
  echo "Usage: ./scripts/e2e_release_escrow.sh <PURCHASE_ID>"
  exit 1
fi

if [ -z "$EMAIL" ] || [ -z "$PASSWORD" ]; then
  echo "Missing credentials."
  echo "Set:"
  echo "  export DEV_EMAIL='...'; export DEV_PASS='...'"
  exit 1
fi

echo "==> 1) Login to get JWT..."
LOGIN_JSON="$(curl -s -X POST "$BASE_URL/v1/auth/login" \
  -H "Content-Type: application/json" \
  --data-binary "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"

echo "Login response:"
echo "$LOGIN_JSON"

# Parse token/org/user as 3 lines (token, org_id, user_id)
PARSED="$(node -e '
const fs = require("fs");
const raw = fs.readFileSync(0, "utf8");
let j;
try { j = JSON.parse(raw || "{}"); } catch { process.exit(13); }

if (j && j.ok === false) {
  console.error("LOGIN_FAILED:", j.error || "UNKNOWN", "-", (j.message || ""));
  process.exit(10);
}

const token =
  j.token ||
  j.accessToken ||
  j.access_token ||
  (j.data && (j.data.token || j.data.accessToken || j.data.access_token)) ||
  "";

const orgId =
  (j.user && (j.user.organization_id || j.user.organizationId)) ||
  (j.data && j.data.user && (j.data.user.organization_id || j.data.user.organizationId)) ||
  j.org ||
  "";

const userId =
  (j.user && (j.user.id || j.user.userId)) ||
  (j.data && j.data.user && (j.data.user.id || j.data.user.userId)) ||
  "";

if (!token) { console.error("LOGIN_FAILED: token not found"); process.exit(11); }
if (!orgId) { console.error("LOGIN_FAILED: organization_id not found"); process.exit(12); }

process.stdout.write(token + "\n" + orgId + "\n" + userId + "\n");
' <<<"$LOGIN_JSON")"

TOKEN="$(printf "%s" "$PARSED" | sed -n '1p' | tr -d '\r')"
ORG_ID="$(printf "%s" "$PARSED" | sed -n '2p' | tr -d '\r')"
USER_ID="$(printf "%s" "$PARSED" | sed -n '3p' | tr -d '\r')"

if [ -z "$TOKEN" ] || [ -z "$ORG_ID" ]; then
  echo "LOGIN_PARSE_FAILED: TOKEN or ORG_ID empty"
  exit 20
fi

echo "==> Token length: ${#TOKEN}"
echo "==> Org ID: $ORG_ID"
[ -n "${USER_ID:-}" ] && echo "==> User ID: $USER_ID"

echo
echo "==> 2) Call release escrow..."
REL_JSON="$(curl -s -i -X POST "$BASE_URL/v1/purchases/$PURCHASE_ID/release-escrow" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -H "Content-Type: application/json" \
  --data-binary '{}')"

echo "$REL_JSON"

echo
echo "==> 3) Verify ledger in DB (wallet_transactions for this purchase)..."
if command -v psql >/dev/null 2>&1; then
  psql -X -P pager=off -d "$DB" -c "
  select
    txn_type::text,
    reference_type,
    reference_id::text,
    amount,
    currency,
    note,
    created_at
  from public.wallet_transactions
  where reference_type='purchase'
    and reference_id::text='${PURCHASE_ID}'
  order by created_at desc
  limit 50;
  " || true
else
  echo "psql not found on PATH. Skipping DB verification."
fi

echo
echo "✅ Done."
