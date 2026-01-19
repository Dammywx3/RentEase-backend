#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Config (safe defaults)
# ---------------------------
API="${API:-http://127.0.0.1:4000}"
DB_NAME="${DB_NAME:-rentease}"

# If you want, you can pre-export PURCHASE_ID before running this script.
# Otherwise it will try to auto-pick the most recent purchase id from DB.
PURCHASE_ID="${PURCHASE_ID:-}"

echo "API=[$API]"
echo "DB_NAME=[$DB_NAME]"

# ---------------------------
# 1) Ensure server is reachable
# ---------------------------
echo ""
echo "==> Checking server ping..."
if ! curl -sS "$API/v1/db/ping" | jq . >/dev/null; then
  echo "❌ Server not reachable at $API"
  echo "   Run: npm run dev"
  exit 1
fi
echo "✅ Server reachable"

# ---------------------------
# 2) Login to get TOKEN (your login.sh sets TOKEN + maybe other vars)
# ---------------------------
echo ""
echo "==> Logging in..."
if [ -x "./scripts/login.sh" ]; then
  # login.sh prints exports; eval them
  eval "$(./scripts/login.sh)"
else
  echo "❌ ./scripts/login.sh not found or not executable"
  exit 1
fi

if [ -z "${TOKEN:-}" ]; then
  echo "❌ TOKEN not set after login"
  exit 1
fi
echo "✅ TOKEN_LEN=${#TOKEN}"

# ---------------------------
# 3) Fetch ORG_ID from /v1/me (avoid null)
# ---------------------------
echo ""
echo "==> Fetching ORG_ID..."
ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id // empty')"
if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
  echo "❌ ORG_ID is empty/null from /v1/me"
  echo "   Response was:"
  curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq .
  exit 1
fi
export ORG_ID
echo "✅ ORG_ID=[$ORG_ID]"

# ---------------------------
# 4) Ensure PURCHASE_ID is set (avoid "" uuid errors)
# ---------------------------
echo ""
echo "==> Resolving PURCHASE_ID..."
if [ -z "$PURCHASE_ID" ]; then
  # get latest purchase id from DB
  PURCHASE_ID="$(psql -d "$DB_NAME" -Atc \
    "select id::text from public.property_purchases where deleted_at is null order by created_at desc limit 1;" \
    | tr -d '[:space:]')"
fi

if [ -z "$PURCHASE_ID" ]; then
  echo "❌ PURCHASE_ID is empty and could not be fetched from DB"
  exit 1
fi
export PURCHASE_ID
echo "✅ PURCHASE_ID=[$PURCHASE_ID]"

# ---------------------------
# 5) Call refund (idempotent) WITH audit fields
# ---------------------------
echo ""
echo "==> Calling refund (idempotent) with audit fields..."

# IMPORTANT: Use jq to build JSON so bash quoting never breaks.
PAYLOAD="$(jq -n \
  --arg refundMethod "card" \
  --arg reason "buyer cancelled" \
  --arg refundPaymentId "21c4d5c8-94b5-4330-b34e-96173d2e4684" \
  --argjson amount 2000 \
  '{refundMethod:$refundMethod, amount:$amount, reason:$reason, refundPaymentId:$refundPaymentId}')"

echo "payload=$PAYLOAD" | cat

RESP="$(curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d "$PAYLOAD")"

echo "$RESP" | jq .

OK="$(echo "$RESP" | jq -r '.ok // false')"
if [ "$OK" != "true" ]; then
  echo "❌ Refund call failed."
  exit 1
fi

# ---------------------------
# 6) Verify DB audit columns
# ---------------------------
echo ""
echo "==> Verifying DB audit fields..."
PAGER=cat psql -d "$DB_NAME" -X -c "
select
  id,
  payment_status,
  refund_method,
  refunded_reason,
  refunded_by,
  refund_payment_id
from public.property_purchases
where id='$PURCHASE_ID'::uuid;
"

echo ""
echo "✅ DONE"
echo "If refund_method/refund_payment_id are still NULL, it's now purely a SERVICE-MAPPING issue (not bash)."
