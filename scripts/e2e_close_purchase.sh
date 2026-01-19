#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${BASE_URL:-http://127.0.0.1:4000}"
DB="${DB:-rentease}"

EMAIL="${DEV_EMAIL:-${EMAIL:-}}"
PASSWORD="${DEV_PASS:-${PASSWORD:-}}"

PURCHASE_ID="${1:-}"
if [ -z "$PURCHASE_ID" ]; then
  echo "Usage: ./scripts/e2e_close_purchase.sh <PURCHASE_ID>"
  exit 1
fi

if [ -z "${EMAIL:-}" ] || [ -z "${PASSWORD:-}" ]; then
  echo "Missing credentials."
  echo "Set:"
  echo "  export DEV_EMAIL='...'; export DEV_PASS='...'"
  exit 1
fi

pick_login_endpoint() {
  # Order matters: your debug/routes shows /v1/auth/auth/login exists
  local candidates=(
    "/v1/auth/auth/login"
    "/v1/auth/login"
    "/v1/auth/auth//login"
  )

  for path in "${candidates[@]}"; do
    local body tmp code
    tmp="/tmp/rentease_login_try_$$.json"
    code="$(curl -s -o "$tmp" -w "%{http_code}" -X POST "$BASE_URL$path" \
      -H "Content-Type: application/json" \
      --data-binary "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)"

    body="$(cat "$tmp" 2>/dev/null || true)"
    rm -f "$tmp"

    # If it's a Fastify 404 message or HTTP != 200, try next
    if [ "$code" != "200" ]; then
      continue
    fi

    # Looks like JSON? accept.
    if echo "$body" | grep -q '{'; then
      echo "$path"
      return 0
    fi
  done

  echo ""
  return 1
}

parse_token_org_user_from_file() {
  local json_file="$1"
  local out_file="$2"

  node -e '
    const fs = require("fs");
    const raw = fs.readFileSync(process.argv[1], "utf8");
    try {
      const j = JSON.parse(raw || "{}");
      const token =
        j.token ||
        j.accessToken ||
        j.access_token ||
        (j.data && (j.data.token || j.data.accessToken || j.data.access_token)) ||
        "";
      const org =
        (j.user && (j.user.organization_id || j.user.organizationId)) ||
        (j.data && j.data.user && (j.data.user.organization_id || j.data.user.organizationId)) ||
        j.org ||
        "";
      const uid =
        (j.user && (j.user.id || j.user.userId)) ||
        (j.data && j.data.user && (j.data.user.id || j.data.user.userId)) ||
        "";
      process.stdout.write(String(token || "") + "\n");
      process.stdout.write(String(org || "") + "\n");
      process.stdout.write(String(uid || "") + "\n");
    } catch (e) {
      process.stdout.write("\n\n\n");
    }
  ' "$json_file" > "$out_file"
}

echo "==> Picking login endpoint..."
LOGIN_PATH="$(pick_login_endpoint || true)"
if [ -z "${LOGIN_PATH:-}" ]; then
  echo "❌ Could not find a working login endpoint."
  echo "Your server routes say login exists under /v1/auth/auth/login."
  echo "Run:"
  echo "  curl -s $BASE_URL/debug/routes | sed -n '1,220p'"
  exit 1
fi
echo "==> Using login endpoint: $LOGIN_PATH"

LOGIN_TMP="/tmp/rentease_login_body_$$.json"
HTTP_CODE="$(curl -s -o "$LOGIN_TMP" -w "%{http_code}" -X POST "$BASE_URL$LOGIN_PATH" \
  -H "Content-Type: application/json" \
  --data-binary "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" || true)"

echo "==> Login HTTP: $HTTP_CODE"
echo "==> Login response:"
cat "$LOGIN_TMP"

if [ "$HTTP_CODE" != "200" ]; then
  echo
  echo "❌ Login failed (HTTP $HTTP_CODE)."
  rm -f "$LOGIN_TMP"
  exit 1
fi

OUT="/tmp/rentease_login_out_$$.txt"
parse_token_org_user_from_file "$LOGIN_TMP" "$OUT"

TOKEN="$(sed -n '1p' "$OUT" | tr -d '\r')"
ORG_ID="$(sed -n '2p' "$OUT" | tr -d '\r')"
USER_ID="$(sed -n '3p' "$OUT" | tr -d '\r')"

rm -f "$LOGIN_TMP" "$OUT"

if [ -z "${TOKEN:-}" ] || [ -z "${ORG_ID:-}" ]; then
  echo
  echo "❌ Login parse failed (token/org missing)."
  echo "Token length: ${#TOKEN}"
  echo "Org length:   ${#ORG_ID}"
  exit 1
fi

echo "==> Token length: ${#TOKEN}"
echo "==> Org ID: $ORG_ID"
[ -n "${USER_ID:-}" ] && echo "==> User ID: $USER_ID"

echo
echo "==> Close purchase..."
CLOSE_RES="$(curl -s -i -X POST "$BASE_URL/v1/purchases/$PURCHASE_ID/close" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -H "Content-Type: application/json" \
  --data-binary '{}')"

echo "$CLOSE_RES" | sed -n '1,220p'

echo
echo "==> Verify purchase status..."
if command -v psql >/dev/null 2>&1; then
  psql -X -P pager=off -d "$DB" -c "
select id::text, status::text, closed_at, updated_at
from public.property_purchases
where id::text='${PURCHASE_ID}'
limit 1;
" || true
else
  echo "psql not found; skipping DB check."
fi

echo
echo "==> Verify audit log (your schema columns)..."
if command -v psql >/dev/null 2>&1; then
  psql -X -P pager=off -d "$DB" -c "
select
  table_name,
  record_id::text,
  operation::text,
  changed_by::text,
  change_details,
  created_at
from public.audit_logs
where record_id::text='${PURCHASE_ID}'
order by created_at desc
limit 10;
" || true
fi

echo
echo "✅ Done."
