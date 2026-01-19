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

perl -0777 -i -pe '
  s/async function upsertRefundMilestones\s*\(\s*\n\s*client:\s*PoolClient,\s*\n\s*args:\s*\{\s*organizationId:\s*string;\s*purchaseId:\s*string;\s*amount:\s*number;\s*lastPaymentId:\s*string\s*\|\s*null\s*\}\s*\n\s*\)\s*\{\s*\n\s*await client\.query\(\s*\n\s*`([\s\S]*?)`/async function upsertRefundMilestones(\n  client: PoolClient,\n  args: {\n    organizationId: string;\n    purchaseId: string;\n    amount: number;\n    lastPaymentId: string | null;\n\n    refundMethod?: string | null;\n    reason?: string | null;\n    refundedBy?: string | null;\n    refundPaymentId?: string | null;\n  }\n) {\n  await client.query(\n    `\n    UPDATE public.property_purchases\n    SET\n      payment_status = \x27refunded\x27::purchase_payment_status,\n      refunded_at = COALESCE(refunded_at, NOW()),\n      refunded_amount = COALESCE(refunded_amount, 0) + \$1::numeric,\n      refund_method = COALESCE(refund_method, \$2::text),\n      refunded_reason = COALESCE(refunded_reason, \$3::text),\n      refunded_by = COALESCE(refunded_by, \$4::uuid),\n      refund_payment_id = COALESCE(refund_payment_id, \$5::uuid),\n      updated_at = NOW()\n    WHERE id = \$6::uuid\n      AND organization_id = \$7::uuid\n      AND deleted_at IS NULL;\n    `/s;

  s/\[\s*args\.amount,\s*args\.purchaseId,\s*args\.organizationId\s*\]/[\n      args.amount,\n      (args.refundMethod ?? null),\n      (args.reason ?? null),\n      (args.refundedBy ?? null),\n      (args.refundPaymentId ?? null),\n      args.purchaseId,\n      args.organizationId,\n    ]/g;
' "$FILE"

perl -0777 -i -pe '
  s/upsertRefundMilestones\(client,\s*\{\s*\n(\s*organizationId:\s*args\.organizationId,\s*\n\s*purchaseId:\s*purchase\.id,\s*\n\s*amount,\s*\n\s*lastPaymentId:\s*purchase\.last_payment_id\s*\?\?\s*null,)/upsertRefundMilestones(client, {\n$1\n\n      refundMethod: (args.refundMethod ?? null),\n      reason: (args.reason ?? null),\n      refundPaymentId: ((args as any).refundPaymentId ?? null),\n      refundedBy: null,\n/smg;
' "$FILE"

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit

echo "✅ PATCHED: $FILE"
