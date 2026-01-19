#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/services/purchase_refunds.service.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$FILE" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

# 1) If already inserted, do nothing
if grep -q 'alreadyRefunded: true' "$FILE" && grep -q 'purchase.payment_status === "refunded"' "$FILE"; then
  echo "ℹ️ idempotent refunded block already present (skipping)"
  exit 0
fi

# 2) Insert block right BEFORE the "if (purchase.payment_status !== "paid")" check
perl -0777 -i -pe '
  s/(\n\s*\/\/ Must be paid before refund[^\n]*\n\s*if\s*\(purchase\.payment_status\s*!==\s*"paid"\)\s*\{)/\n  \/\/ If already refunded, be idempotent (return success)\n  if (purchase.payment_status === "refunded" || purchase.refunded_at) {\n    const updated = await getPurchase(client, {\n      organizationId: args.organizationId,\n      purchaseId: purchase.id,\n    });\n    return { purchase: updated, alreadyRefunded: true, platformFeeReversed: 0, sellerReversed: 0 };\n  }\n$1/s
' "$FILE"

# 3) Sanity check
grep -q 'purchase.payment_status === "refunded"' "$FILE" || {
  echo "❌ Patch failed: refunded idempotent block not found."
  exit 1
}

echo "✅ PATCHED: $FILE"
echo "NEXT:"
echo "  1) npm run dev"
echo "  2) Call refund again (should return alreadyRefunded=true):"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000}' | jq"
