#!/usr/bin/env bash
set -Eeuo pipefail

# Must run in bash (not zsh)
if [ -z "${BASH_VERSION:-}" ]; then
  echo "❌ This script must be run with bash, not sourced in zsh."
  echo "Run: DB_NAME=rentease bash scripts/dev_seed_unpaid_purchase_safe.sh"
  return 1 2>/dev/null || exit 1
fi

# Detect if script is SOURCED vs EXECUTED (bash only)
SOURCED=0
if [ "${BASH_SOURCE[0]}" != "$0" ]; then
  SOURCED=1
fi

die() {
  echo "❌ $*" >&2
  if [ "$SOURCED" -eq 1 ]; then
    return 1
  else
    exit 1
  fi
}

trap 'rc=$?; echo "❌ ERROR rc=$rc at line $LINENO: $BASH_COMMAND" >&2; if [ "$SOURCED" -eq 1 ]; then return $rc; else exit $rc; fi' ERR

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || die "Failed to cd into ROOT=$ROOT"

: "${DB_NAME:=rentease}"
: "${API:=http://127.0.0.1:4000}"

echo "==> ROOT=$ROOT"
echo "==> DB_NAME=$DB_NAME"
echo "==> API=$API"

command -v psql >/dev/null 2>&1 || die "psql not found in PATH"
command -v jq   >/dev/null 2>&1 || die "jq not found in PATH"
command -v curl >/dev/null 2>&1 || die "curl not found in PATH"

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

  [ -n "${TOKEN:-}" ] || die "Could not get TOKEN from scripts/login.sh output. Output was: $LOGIN_OUT"
  export TOKEN
fi

echo "==> TOKEN_LEN=${#TOKEN}"

ORG_ID="$(curl -sS --max-time 15 "$API/v1/me" -H "Authorization: Bearer $TOKEN" | jq -r '.data.organization_id // empty')" || true
USER_ID="$(curl -sS --max-time 15 "$API/v1/me" -H "Authorization: Bearer $TOKEN" | jq -r '.data.id // empty')" || true

[ -n "$ORG_ID" ] || die "ORG_ID empty. Is API running? Is TOKEN valid?"
[ -n "$USER_ID" ] || die "USER_ID empty. Is API running? Is TOKEN valid?"

export ORG_ID USER_ID
echo "==> ORG_ID=$ORG_ID"
echo "==> USER_ID=$USER_ID"

PROPERTY_ID="$(
  PAGER=cat psql -q -X -d "$DB_NAME" -t -A -v ON_ERROR_STOP=1 -c "
  select p.id::text
  from public.properties p
  where p.organization_id='$ORG_ID'::uuid
    and p.deleted_at is null
  order by p.created_at desc
  limit 1;"
)"
PROPERTY_ID="$(echo "$PROPERTY_ID" | tr -d '[:space:]')"
[ -n "$PROPERTY_ID" ] || die "No property found for ORG_ID=$ORG_ID"

LISTING_ID="$(
  PAGER=cat psql -q -X -d "$DB_NAME" -t -A -v ON_ERROR_STOP=1 -c "
  select l.id::text
  from public.property_listings l
  where l.organization_id='$ORG_ID'::uuid
    and l.property_id='$PROPERTY_ID'::uuid
    and l.deleted_at is null
  order by l.created_at desc
  limit 1;"
)"
LISTING_ID="$(echo "$LISTING_ID" | tr -d '[:space:]')"
[ -n "$LISTING_ID" ] || die "No listing found for PROPERTY_ID=$PROPERTY_ID"

echo "==> PROPERTY_ID=$PROPERTY_ID"
echo "==> LISTING_ID=$LISTING_ID"

PURCHASE_ID="$(
  PAGER=cat psql -q -X -d "$DB_NAME" -v ON_ERROR_STOP=1 -t -A <<SQL
WITH ins AS (
  INSERT INTO public.property_purchases(
    organization_id, property_id, listing_id,
    buyer_id, seller_id,
    agreed_price, currency,
    status, payment_status,
    created_at, updated_at
  ) VALUES (
    '$ORG_ID'::uuid,
    '$PROPERTY_ID'::uuid,
    '$LISTING_ID'::uuid,
    '$USER_ID'::uuid,
    '$USER_ID'::uuid,
    2000,
    'USD',
    'under_contract'::purchase_status,
    'unpaid'::purchase_payment_status,
    now(), now()
  )
  RETURNING id::text
)
SELECT id AS purchase_id FROM ins \gset
\echo :purchase_id
SQL
)"
PURCHASE_ID="$(echo "$PURCHASE_ID" | tr -d '[:space:]')"
[ -n "$PURCHASE_ID" ] || die "Failed to create purchase (no id returned)."

echo "✅ NEW_PURCHASE_ID=[$PURCHASE_ID]"

echo "==> DB check:"
PAGER=cat psql -q -d "$DB_NAME" -X -v ON_ERROR_STOP=1 -c "
select id::text, status::text, payment_status::text, created_at
from public.property_purchases
where id='$PURCHASE_ID'::uuid;"

echo "✅ Done."
