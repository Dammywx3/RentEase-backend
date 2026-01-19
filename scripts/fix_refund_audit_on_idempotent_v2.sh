#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/services/purchase_refunds.service.ts"

if [ ! -f "$FILE" ]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

# Prevent double-insert
if grep -q "IDEMPOTENT_REFUND_AUDIT_V2" "$FILE"; then
  echo "ℹ️ Already patched (marker found)."
  exit 0
fi

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$FILE" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

perl -0777 -i -pe '
  my $marker = "  // IDEMPOTENT_REFUND_AUDIT_V2\n";
  my $block = $marker . q{
  // If already refunded, be idempotent BUT still persist audit fields (only if empty)
  if (purchase.payment_status === "refunded" || purchase.refunded_at) {
    await client.query(
      `
      UPDATE public.property_purchases
      SET
        refund_method      = COALESCE(refund_method, $1::text),
        refunded_reason    = COALESCE(refunded_reason, $2::text),
        refunded_by        = COALESCE(refunded_by, $3::uuid),
        refund_payment_id  = COALESCE(refund_payment_id, $4::uuid),
        updated_at         = NOW()
      WHERE id = $5::uuid
        AND organization_id = $6::uuid;
      `,
      [
        (args as any).refundMethod ?? null,
        args.reason ?? null,
        (args as any).refundedByUserId ?? null,
        (args as any).refundPaymentId ?? null,
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

};

  # Insert right after the first getPurchase(...) call finishes (the statement ending with ");
  # We match from: const purchase = await getPurchase(...);  (across newlines)
  if (s/(const\s+purchase\s*=\s*await\s+getPurchase\([\s\S]*?\);\s*)/$1$block/s) {
    $_;
  } else {
    die "❌ Could not find getPurchase(...) assignment to insert after.\\n";
  }
' "$FILE"

echo "✅ PATCHED: $FILE"
echo ""
echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"
echo ""
echo "NEXT:"
echo "  1) npm run dev"
echo "  2) Re-call refund with audit fields"
echo "  3) Verify DB columns populate"
