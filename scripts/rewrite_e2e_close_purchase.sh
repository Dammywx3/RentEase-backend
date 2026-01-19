#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/e2e_close_purchase.sh"

cat > "$FILE" <<'EOSH'
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

# -------- helpers --------

discover_login_path() {
  # Default candidates (we’ll try in order)
  local candidates=(
    "/v1/auth/login"
    "/v1/auth/auth/login"
    "/v1/auth/auth//login"
  )

  # Try discover from debug/routes (best-effort)
  local routes=""
  routes="$(curl -s "$BASE_URL/debug/routes" 2>/dev/null || true)"

  # If routes contains "login (POST)" under something like ".../auth/auth/login"
  # We'll extract a reasonable guess. We know your tree shows: v1/ a/ uth/auth/ login (POST)
  # That corresponds to /v1/auth/auth/login in practice.
  if echo "$routes" | grep -q "login (POST)"; then
    # prefer /v1/auth/auth/login if present
    if echo "$routes" | grep -q "uth/auth/.*login (POST)"; then
      echo "/v1/auth/auth/login"
      return 0
    fi
  fi

  # Fallback to first candidate
  echo "${candidates[0]}"
}

# Parse login JSON from stdin and set TOKEN/ORG_ID/USER_ID in current shell (NO PIPE SUBSHELL)
parse_token_org_user() {
  local tmp="/tmp/rentease_login_parse_$$.txt"
  cat > "$tmp"  # read stdin fully into tmp

  # Use node to parse; print 3 lines: token, org, user
  local out="/tmp/rentease_login_out_$$.txt"
  node - <<'NODE' < "$tmp" > "$out"
let raw = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", c => raw += c);
process.stdin.on("end", () => {
  try {
    const j = JSON.parse(raw || "{}");

    const ok = j && j.ok;
    if (ok === false) {
      // still output blanks so bash can handle it
      process.stdout.write("\n\n\n");
      process.exit(0);
    }

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
});
NODE

  TOKEN="$(sed -n '1p' "$out" | tr -d '\r')"
  ORG_ID="$(sed -n '2p' "$out" | tr -d '\r')"
  USER_ID="$(sed -n '3p' "$out" | tr -d '\r')"

  rm -f "$tmp" "$out"
}

die_login_parse_debug() {
  local body="$1"
  echo "❌ Login parse failed (token/org missing). DEBUG:"
  echo "==> token length: ${#TOKEN}"
  echo "==> org   length: ${#ORG_ID}"
  echo
  echo "==> First 200 chars of login JSON:"
  echo "$body" | head -c 200
  echo
  echo "==> Does JSON contain 'token' key?"
  echo "$body" | grep -o '"token"' | head -n 5 || true
  echo "==> Does JSON contain 'organization_id' key?"
  echo "$body" | grep -o '"organization_id"' | head -n 5 || true
  echo
  echo "==> If this still fails, run:"
  echo "   node -e 'console.log(JSON.parse(fs.readFileSync(0,\"utf8\")))' <<<\"$body\""
  exit 1
}

# -------- flow --------

echo "==> Login autodetect..."
LOGIN_PATH="$(discover_login_path)"
echo "==> Using login endpoint: $LOGIN_PATH"

LOGIN_BODY="$(curl -s -X POST "$BASE_URL$LOGIN_PATH" \
  -H "Content-Type: application/json" \
  --data-binary "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")"

echo "==> Login response:"
echo "$LOGIN_BODY"

# IMPORTANT: DO NOT PIPE into function (subshell). Use here-string to feed stdin.
TOKEN=""
ORG_ID=""
USER_ID=""
parse_token_org_user <<<"$LOGIN_BODY"

if [ -z "${TOKEN:-}" ] || [ -z "${ORG_ID:-}" ]; then
  die_login_parse_debug "$LOGIN_BODY"
fi

echo "==> Token length: ${#TOKEN}"
echo "==> Org ID: $ORG_ID"
[ -n "${USER_ID:-}" ] && echo "==> User ID: $USER_ID"

echo
echo "==> Close purchase..."
# Your route tree shows close at: /v1/purchases/:id|:purchaseId/close
# We'll call the canonical one:
CLOSE_RES="$(curl -s -i -X POST "$BASE_URL/v1/purchases/$PURCHASE_ID/close" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -H "Content-Type: application/json" \
  --data-binary '{}')"

echo "$CLOSE_RES" | sed -n '1,200p'

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
echo "==> Verify audit log (your schema: table_name, record_id, operation, changed_by, change_details)..."
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
where table_name in ('property_purchases','purchases','purchase')
  and record_id::text='${PURCHASE_ID}'
order by created_at desc
limit 10;
" || true
fi

echo
echo "✅ Done."
EOSH

chmod +x "$FILE"

echo "✅ Rewrote: $FILE"
echo "Run:"
echo "  export DEV_EMAIL='dev_1768638237@rentease.local'"
echo "  export DEV_PASS='Passw0rd!234'"
echo "  ./scripts/e2e_close_purchase.sh 5ae53ce5-433d-4966-a1e8-edb8d0f6d1ae"
