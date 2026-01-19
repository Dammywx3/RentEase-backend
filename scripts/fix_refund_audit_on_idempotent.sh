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

# Replace the early-return "already refunded" block to also write audit fields (COALESCE) without changing refunded_amount.
perl -0777 -i -pe '
  s{
    //\s*If already refunded, be idempotent \(return success\)\s*
    if\s*\(purchase\.payment_status\s*===\s*"refunded"\s*\|\|\s*purchase\.refunded_at\)\s*\{\s*
      const\s+updated\s*=\s*await\s+getPurchase\(client,\s*\{\s*
        organizationId:\s*args\.organizationId,\s*
        purchaseId:\s*purchase\.id,\s*
      \}\);\s*
      return\s*\{\s*purchase:\s*updated,\s*alreadyRefunded:\s*true,\s*platformFeeReversed:\s*0,\s*sellerReversed:\s*0\s*\};\s*
    \}
  }{
    // If already refunded, be idempotent (return success) BUT still store audit fields (one-time, COALESCE)
    if (purchase.payment_status === "refunded" || purchase.refunded_at) {
      await client.query(
        `
        UPDATE public.property_purchases
        SET
          refund_method = COALESCE(refund_method, $1),
          refunded_reason = COALESCE(refunded_reason, $2),
          refunded_by = COALESCE(refunded_by, NULLIF($3, \x27\x27)::uuid),
          refund_payment_id = COALESCE(refund_payment_id, NULLIF($4, \x27\x27)::uuid),
          updated_at = NOW()
        WHERE id = $5::uuid
          AND organization_id = $6::uuid;
        `,
        [
          args.refundMethod ?? null,
          args.reason ?? null,
          args.refundedByUserId ?? null,
          args.refundPaymentId ?? null,
          purchase.id,
          args.organizationId,
        ]
      );

      const updated = await getPurchase(client, {
        organizationId: args.organizationId,
        purchaseId: purchase.id,
      });
      return { purchase: updated, alreadyRefunded: true, platformFeeReversed: 0, sellerReversed: 0 };
    }
  }xs or die "❌ Could not patch already-refunded idempotent block (pattern not found).\\n";
' "$FILE"

echo "✅ PATCHED: $FILE"
echo ""
echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"
echo ""
echo "NEXT:"
echo "  1) npm run dev"
echo "  2) Call refund again with audit fields and verify DB columns populate."
