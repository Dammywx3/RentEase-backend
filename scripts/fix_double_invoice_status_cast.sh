#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/services/rent_invoices.service.ts"

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "$ROOT/scripts/.bak/rent_invoices.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$ts"

perl -0777 -i -pe "s/'paid'::invoice_status::invoice_status/'paid'::invoice_status/g" "$FILE"

echo "✅ Cleaned double cast"
grep -n "status = 'paid'" "$FILE" || true
echo "➡️ Restart server: npm run dev"
