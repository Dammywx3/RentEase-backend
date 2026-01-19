#!/usr/bin/env bash
set -euo pipefail

FILE="scripts/e2e_close_purchase.sh"
if [ ! -f "$FILE" ]; then
  echo "❌ Missing $FILE"
  exit 1
fi

cp -f "$FILE" "$FILE.bak.$(date +%s)"

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
  echo "Set credentials first:"
  echo "  export DEV_EMAIL='dev_...@rentease.local'"
  echo "  export DEV_PASS='Passw0rd!234'"
  exit 1
fi

# ---- helpers ----
try_login() {
  local path="$1"
  # Return: "HTTP_CODE|BODY"
  local resp
  resp="$(curl -s -i -X POST "$BASE_URL$path" \
    -H "Content-Type: application/json" \
    --data-binary "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" )"
  local code
  code="$(printf "%s" "$resp" | head -n 1 | awk '{print $2}')"
  local body
  body="$(printf "%s" "$resp" | awk 'BEGIN{p=0} /^\r?$/{p=1; next} {if(p) print}' )"
  printf "%s|%s" "${code:-000}" "$body"
}

parse_token_org_user() {
  local json="$1"
  local tmp="/tmp/rentease_login_parse_$$.txt"
  printf "%s" "$json" | node - <<'NODE' > "$tmp"
let raw="";
process.stdin.setEncoding("utf8");
process.stdin.on("data",(c)=>raw+=c);
process.stdin.on("end",()=>{
  try{
    const j=JSON.parse(raw||"{}");
    const token=j.token || j.accessToken || j.access_token || (j.data && (j.data.token||j.data.accessToken||j.data.access_token)) || "";
    const org=(j.user && (j.user.organization_id||j.user.organizationId)) || (j.data && j.data.user && (j.data.user.organization_id||j.data.user.organizationId)) || j.org || "";
    const uid=(j.user && (j.user.id||j.user.userId)) || (j.data && j.data.user && (j.data.user.id||j.data.user.userId)) || "";
    console.log(token); console.log(org); console.log(uid);
  }catch(e){
    console.log(""); console.log(""); console.log("");
  }
});
NODE
  TOKEN="$(sed -n '1p' "$tmp" | tr -d '\r')"
  ORG_ID="$(sed -n '2p' "$tmp" | tr -d '\r')"
  USER_ID="$(sed -n '3p' "$tmp" | tr -d '\r')"
  rm -f "$tmp"
}

echo "==> Login autodetect..."

CANDIDATES=(
  "/v1/auth/login"
  "/v1/auth/auth/login"
  "/v1/uth/auth/login"
  "/v1/authentication/login"
)

LOGIN_BODY=""
LOGIN_PATH=""

for p in "${CANDIDATES[@]}"; do
  out="$(try_login "$p")"
  code="${out%%|*}"
  body="${out#*|}"

  if [ "$code" = "404" ] || [ "$code" = "405" ] || [ "$code" = "000" ]; then
    continue
  fi

  # if it's not 404, we assume this is the right endpoint
  LOGIN_PATH="$p"
  LOGIN_BODY="$body"
  break
done

if [ -z "$LOGIN_PATH" ]; then
  echo "❌ Could not find a working login endpoint."
  echo "Try:"
  echo "  curl -s $BASE_URL/debug/routes | sed -n '1,220p'"
  exit 2
fi

echo "==> Using login endpoint: $LOGIN_PATH"
echo "==> Login response:"
echo "$LOGIN_BODY"

parse_token_org_user "$LOGIN_BODY"

if [ -z "${TOKEN:-}" ] || [ -z "${ORG_ID:-}" ]; then
  echo "❌ Login parse failed (token/org missing)."
  exit 3
fi

echo "==> Token length: ${#TOKEN}"
echo "==> Org ID: $ORG_ID"
[ -n "${USER_ID:-}" ] && echo "==> User ID: $USER_ID"

echo
echo "==> Close purchase..."
curl -s -i -X POST "$BASE_URL/v1/purchases/$PURCHASE_ID/close" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -H "Content-Type: application/json" \
  --data-binary '{}' | sed -n '1,220p'

echo
echo "==> Verify purchase status..."
psql -X -P pager=off -d "$DB" -c "
select id::text, status::text, closed_at, updated_at
from public.property_purchases
where id::text='${PURCHASE_ID}'
limit 1;
" || true

echo
echo "==> Verify audit log (table_name/operation/record_id/change_details)..."
psql -X -P pager=off -d "$DB" -c "
select
  table_name,
  operation::text as operation,
  record_id::text as record_id,
  changed_by::text as changed_by,
  change_details,
  created_at
from public.audit_logs
where record_id::text='${PURCHASE_ID}'
order by created_at desc
limit 10;
" || true

echo
echo "✅ Done."
EOSH

chmod +x "$FILE"
echo "✅ Patched $FILE (login autodetect + retries)"
echo "Run:"
echo "  export DEV_EMAIL='dev_1768638237@rentease.local'"
echo "  export DEV_PASS='Passw0rd!234'"
echo "  ./scripts/e2e_close_purchase.sh 5ae53ce5-433d-4966-a1e8-edb8d0f6d1ae"
