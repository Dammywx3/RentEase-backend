#!/usr/bin/env bash
set -Eeuo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "❌ Run with bash: DB_NAME=rentease bash scripts/dev_seed_unpaid_purchase_safe_v3.sh"
  exit 1
fi

trap 'rc=$?; echo "❌ ERROR rc=$rc at line $LINENO: $BASH_COMMAND" >&2; exit $rc' ERR

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

: "${DB_NAME:=rentease}"
: "${API:=http://127.0.0.1:4000}"

echo "==> ROOT=$ROOT"
echo "==> DB_NAME=$DB_NAME"
echo "==> API=$API"

command -v psql >/dev/null 2>&1 || { echo "❌ psql not found"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "❌ jq not found"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ curl not found"; exit 1; }

# -----------------------------
# SAFE login: DO NOT eval
# -----------------------------
if [ -z "${TOKEN:-}" ]; then
  echo "==> TOKEN not set. Running ./scripts/login.sh (safe parse)..."
  LOGIN_OUT="$(./scripts/login.sh 2>&1 || true)"

  TOKEN="$(printf "%s\n" "$LOGIN_OUT" | sed -nE 's/^export[[:space:]]+TOKEN="?([^"]+)"?$/\1/p' | head -n 1)"
  LOGIN_API="$(printf "%s\n" "$LOGIN_OUT" | sed -nE 's/^export[[:space:]]+API="?([^"]+)"?$/\1/p' | head -n 1)"

  if [ -n "${LOGIN_API:-}" ]; then
    API="$LOGIN_API"
    export API
  fi

  if [ -z "${TOKEN:-}" ]; then
    echo "❌ Could not get TOKEN from scripts/login.sh output."
    printf "%s\n" "$LOGIN_OUT"
    exit 1
  fi
  export TOKEN
fi

echo "==> TOKEN_LEN=${#TOKEN}"

export ORG_ID="$(curl -sS --max-time 15 "$API/v1/me" -H "Authorization: Bearer $TOKEN" | jq -r '.data.organization_id // empty')"
export USER_ID="$(curl -sS --max-time 15 "$API/v1/me" -H "Authorization: Bearer $TOKEN" | jq -r '.data.id // empty')"

[ -n "${ORG_ID:-}" ] || { echo "❌ ORG_ID empty"; exit 1; }
[ -n "${USER_ID:-}" ] || { echo "❌ USER_ID empty"; exit 1; }

echo "==> ORG_ID=$ORG_ID"
echo "==> USER_ID=$USER_ID"

TS="$(date +%Y%m%d_%H%M%S)"
SQL_FILE="scripts/.tmp_seed_unpaid_purchase_safe_v3.${TS}.sql"

cat > "$SQL_FILE" <<SQL
BEGIN;

WITH candidate AS (
  SELECT
    p.id::uuid  AS property_id,
    l.id::uuid  AS listing_id
  FROM public.properties p
  JOIN public.property_listings l
    ON l.organization_id = p.organization_id
   AND l.property_id = p.id
   AND l.deleted_at IS NULL
  WHERE p.organization_id = '$ORG_ID'::uuid
    AND p.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1
      FROM public.property_purchases pp
      WHERE pp.organization_id = p.organization_id
        AND pp.property_id = p.id
        AND pp.deleted_at IS NULL
        AND pp.status::text NOT IN ('cancelled','refunded','closed')
    )
  ORDER BY p.created_at DESC
  LIMIT 1
),
ins AS (
  INSERT INTO public.property_purchases(
    organization_id, property_id, listing_id,
    buyer_id, seller_id,
    agreed_price, currency,
    status, payment_status,
    created_at, updated_at
  )
  SELECT
    '$ORG_ID'::uuid,
    c.property_id,
    c.listing_id,
    '$USER_ID'::uuid,
    '$USER_ID'::uuid,
    2000,
    'USD',
    'under_contract'::purchase_status,
    'unpaid'::purchase_payment_status,
    now(), now()
  FROM candidate c
  RETURNING id::text
),
fallback AS (
  SELECT pp.id::text AS id
  FROM public.property_purchases pp
  WHERE pp.organization_id = '$ORG_ID'::uuid
    AND pp.deleted_at IS NULL
    AND pp.status::text NOT IN ('cancelled','refunded','closed')
  ORDER BY pp.created_at DESC
  LIMIT 1
)
SELECT id FROM ins
UNION ALL
SELECT id FROM fallback
LIMIT 1;

COMMIT;
SQL

echo "==> Writing $SQL_FILE"
echo "==> Applying..."

RAW_OUT="$(PAGER=cat psql -q -d "$DB_NAME" -X -v ON_ERROR_STOP=1 -t -A -f "$SQL_FILE")"

# Extract exactly one UUID from whatever psql printed
PURCHASE_ID="$(printf "%s" "$RAW_OUT" | tr -d '\r\n' | sed -nE 's/.*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}).*/\1/p' | head -n 1)"

if [ -z "${PURCHASE_ID:-}" ]; then
  echo "❌ Could not extract purchase UUID from psql output."
  echo "==> Raw output was:"
  printf "%s\n" "$RAW_OUT"
  exit 1
fi

echo "✅ NEW_PURCHASE_ID=[$PURCHASE_ID]"

echo "==> DB check:"
PAGER=cat psql -d "$DB_NAME" -X -v ON_ERROR_STOP=1 -c "
select id::text, property_id::text, listing_id::text, status::text, payment_status::text, created_at
from public.property_purchases
where id='$PURCHASE_ID'::uuid;"

echo "✅ Done."
