#!/usr/bin/env bash
set -euo pipefail

TS="$(date +%Y%m%d_%H%M%S)"
FILE="src/services/purchase_refunds.service.ts"
mkdir -p scripts/.bak

cp "$FILE" "scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

# Remove the strict comparison that triggers TS2367
# From:
# if (purchase.refunded_at || purchase.payment_status === "refunded" || (debits.hasPayee && debits.hasFee)) {
# To:
# if (purchase.refunded_at || (debits.hasPayee && debits.hasFee)) {
perl -0777 -i -pe '
s/if\s*\(\s*purchase\.refunded_at\s*\|\|\s*purchase\.payment_status\s*===\s*"refunded"\s*\|\|\s*\(debits\.hasPayee\s*&&\s*debits\.hasFee\)\s*\)\s*\{/if (purchase.refunded_at || (debits.hasPayee && debits.hasFee)) {/g
' "$FILE"

# Verify it changed
if grep -q 'payment_status === "refunded"' "$FILE"; then
  echo "❌ Still found payment_status === \"refunded\" in $FILE"
  exit 1
fi

echo "✅ patched: $FILE"
echo ""
echo "🔎 Typecheck..."
npx -y tsc -p tsconfig.json --noEmit
echo ""
echo "✅ DONE"
echo "NEXT: npm run dev"
