#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/purchase_refunds.service.ts"
TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak
cp "$FILE" "scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

perl -0777 -i -pe '
  s/if\s*\(\s*purchase\.refunded_at\s*\|\|\s*purchase\.payment_status\s*===\s*"refunded"\s*\)\s*\{/if (purchase.refunded_at) {/g;
' "$FILE"

# sanity check
if grep -n 'payment_status === "refunded"' "$FILE" >/dev/null 2>&1; then
  echo "❌ Patch failed: still found payment_status === \"refunded\""
  exit 1
fi

echo "✅ PATCHED: $FILE"
echo "🔎 Typecheck..."
npx -y tsc -p tsconfig.json --noEmit
echo "✅ OK"
echo ""
echo "NEXT:"
echo "  npm run dev"
