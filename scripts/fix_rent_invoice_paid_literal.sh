#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/services/rent_invoices.service.ts"

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "$ROOT/scripts/.bak/rent_invoices.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$ts"

# Replace unquoted paid token in SQL assignments/conditions: status = paid  -> status = 'paid'::invoice_status
perl -0777 -i -pe '
  my $c=0;

  # common: status = paid
  $c += s/status\s*=\s*paid\b/status = \x27paid\x27::invoice_status/g;

  # common: status=paid::invoice_status (missing quotes)
  $c += s/status\s*=\s*paid::invoice_status/status = \x27paid\x27::invoice_status/g;

  # common: WHERE status = paid
  $c += s/(\bstatus\s*=\s*)paid\b/${1}\x27paid\x27::invoice_status/g;

  END { print STDERR "patched=$c\n"; }
' "$FILE"

echo "---- verify paid lines"
grep -n "paid" "$FILE" | sed -n '1,120p' || true

echo "✅ Patched paid literal in: src/services/rent_invoices.service.ts"
echo "➡️ Restart server: npm run dev"
