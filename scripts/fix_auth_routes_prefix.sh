#!/usr/bin/env bash
set -euo pipefail

FILE="src/routes/auth.ts"
STAMP="$(date +%Y%m%d_%H%M%S)"

if [[ ! -f "$FILE" ]]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak.${STAMP}"

# Replace app.post("/auth/login"...) -> app.post("/login"...)
perl -0777 -i -pe 's/(app\.(get|post|put|patch|delete)\()\s*"\s*\/auth\/login\s*"/$1"\/login"/g' "$FILE"
perl -0777 -i -pe 's/(app\.(get|post|put|patch|delete)\()\s*"\s*\/auth\/register\s*"/$1"\/register"/g' "$FILE"

# Also fix any "/auth" base paths used directly (rare but happens)
# Example: app.post("/auth/logout") -> app.post("/logout")
perl -0777 -i -pe 's/(app\.(get|post|put|patch|delete)\()\s*"\s*\/auth\//$1"\//g' "$FILE"

echo "============================================================"
echo "✅ Patched: $FILE"
echo "Backup: ${FILE}.bak.${STAMP}"
echo "============================================================"
echo "Now run:"
echo "  npm run build"
echo "  # restart server (if needed): npm run dev"
echo "  curl -s http://127.0.0.1:4000/debug/routes | rg -n \"auth|login|register\" | head -n 60"
echo "============================================================"
