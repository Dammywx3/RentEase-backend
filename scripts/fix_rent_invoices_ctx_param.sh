#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/routes/rent_invoices.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Missing: $FILE"
  exit 1
fi

# Backup
cp "$FILE" "$ROOT/scripts/rent_invoices.ts.bak.$(date +%Y%m%d_%H%M%S)"

# Remove the invalid set_config line only
perl -0777 -i -pe 's/,\s*set_config\(\x27request\.header\.x-organization-id\x27,\s*\$3,\s*true\)\s*//g' "$FILE"

echo "✅ Removed invalid set_config('request.header.x-organization-id',...) from rent_invoices.ts"
echo "➡️ Restart: npm run dev"
