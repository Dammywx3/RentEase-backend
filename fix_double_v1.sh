#!/usr/bin/env bash
set -euo pipefail

ROUTES_DIR="src/routes"

# If API env var is missing, default to local server
API_BASE="${API:-http://127.0.0.1:4000}"

if [ ! -d "$ROUTES_DIR" ]; then
  echo "❌ Can't find $ROUTES_DIR (run this from your project root)."
  exit 1
fi

echo "🔎 Fixing duplicate /v1 usage inside route modules (NO rg needed)..."

FILES="$(find "$ROUTES_DIR" -type f -name "*.ts" ! -name "index.ts" -print)"

if [ -z "$FILES" ]; then
  echo "⚠️ No route files found under $ROUTES_DIR"
  exit 0
fi

echo
echo "---- Matches BEFORE (grep) ----"
# Show any route literals that include /v1/ and any register prefix /v1
# shellcheck disable=SC2086
grep -nH '"/v1/' $FILES 2>/dev/null || true
# shellcheck disable=SC2086
grep -nH "'/v1/" $FILES 2>/dev/null || true
# shellcheck disable=SC2086
grep -nH 'prefix:[[:space:]]*"/v1"' $FILES 2>/dev/null || true
# shellcheck disable=SC2086
grep -nH "prefix:[[:space:]]*'/v1'" $FILES 2>/dev/null || true

# Apply fixes with backups
while IFS= read -r f; do
  [ -z "$f" ] && continue

  # A) Remove "/v1/" from quoted path literals: "/v1/auth/login" -> "/auth/login"
  perl -pi.bak -e 's{(["'"'"'])/v1/}{$1/}g' "$f"

  # B) Remove app.register(..., { prefix: "/v1" })
  perl -pi.bak -0777 -e 's{(\bregister\s*\([^;]*?),\s*\{\s*prefix\s*:\s*["'"'"']\/v1["'"'"']\s*,?\s*\}\s*\)}{$1)}gs' "$f"
done <<EOF
$FILES
EOF

echo
echo "---- Matches AFTER (grep) ----"
# shellcheck disable=SC2086
grep -nH '"/v1/' $FILES 2>/dev/null || true
# shellcheck disable=SC2086
grep -nH "'/v1/" $FILES 2>/dev/null || true
# shellcheck disable=SC2086
grep -nH 'prefix:[[:space:]]*"/v1"' $FILES 2>/dev/null || true
# shellcheck disable=SC2086
grep -nH "prefix:[[:space:]]*'/v1'" $FILES 2>/dev/null || true

echo
echo "✅ Done. Backups created as *.bak"
echo
echo "🔁 Restart your server now, then I will fetch routes from:"
echo "   $API_BASE/debug/routes"
echo
echo "➡️ Run:"
echo "   curl -sS \"$API_BASE/debug/routes\""
echo
echo "Rollback (if needed):"
echo "  find $ROUTES_DIR -type f -name '*.bak' -print0 | while IFS= read -r -d '' b; do mv \"\$b\" \"\${b%.bak}\"; done"
