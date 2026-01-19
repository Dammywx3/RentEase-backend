#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="${1:-20260116_125859}"

SVC="$ROOT/src/services/purchase_refunds.service.ts"
ROUTES="$ROOT/src/routes/purchases.routes.ts"
BAK="$ROOT/scripts/.bak"

SVC_BAK="$BAK/purchase_refunds.service.ts.bak.$TS"
ROUTES_BAK="$BAK/purchases.routes.ts.bak.$TS"

if [ ! -f "$SVC_BAK" ]; then
  echo "❌ Missing backup: $SVC_BAK"
  echo "Tip: ls -1 $BAK | tail -n 20"
  exit 1
fi
if [ ! -f "$ROUTES_BAK" ]; then
  echo "❌ Missing backup: $ROUTES_BAK"
  echo "Tip: ls -1 $BAK | tail -n 20"
  exit 1
fi

echo "==> restoring from backups ($TS)"
cp "$SVC_BAK" "$SVC"
cp "$ROUTES_BAK" "$ROUTES"
echo "✅ restored: $SVC"
echo "✅ restored: $ROUTES"

echo "==> patching service (valid perl)"

perl -0777 -i -pe '
  # Add audit fields into PropertyPurchaseRow if missing
  if ($_ !~ /refund_method:\s*string\s*\|\s*null;/) {
    s/(refunded_amount:\s*string\s*\|\s*null;\s*\n\};)/refunded_amount: string | null;\n\n  refund_method: string | null;\n  refunded_reason: string | null;\n  refunded_by: string | null;\n  refund_payment_id: string | null;\n};/s;
  }

  # Add audit fields into PURCHASE_SELECT if missing
  if ($_ !~ /pp\.refund_method::text\s+AS\s+refund_method/) {
    s/(pp\.refunded_amount::text\s+AS\s+refunded_amount\s*)/pp.refunded_amount::text AS refunded_amount,\n\n  pp.refund_method::text AS refund_method,\n  pp.refunded_reason::text AS refunded_reason,\n  pp.refunded_by::text AS refunded_by,\n  pp.refund_payment_id::text AS refund_payment_id/s;
  }

  # Extend refundPropertyPurchase args if missing (audit params)
  if ($_ !~ /refundPaymentId\?:\s*string\s*\|\s*null/) {
    s/(refundMethod\?:\s*RefundMethod;[^\n]*\n)/$1    refundPaymentId?: string | null;\n    refundedByUserId?: string | null;\n/s;
  }

  # Replace upsertRefundMilestones with audit-capable version if missing refund_method assignment
  if ($_ !~ /refund_method\s*=\s*COALESCE\(/) {
    s/async function upsertRefundMilestones\([\s\S]*?\)\s*\{\s*await client\.query\([\s\S]*?\);\s*\}/async function upsertRefundMilestones(\n  client: PoolClient,\n  args: {\n    organizationId: string;\n    purchaseId: string;\n    amount: number;\n    refundMethod: RefundMethod | null;\n    reason: string | null;\n    refundedByUserId: string | null;\n    refundPaymentId: string | null;\n  }\n) {\n  await client.query(\n    `\n    UPDATE public.property_purchases\n    SET\n      payment_status = \x27refunded\x27::purchase_payment_status,\n      refunded_at = COALESCE(refunded_at, NOW()),\n      refunded_amount = COALESCE(refunded_amount, 0) + $1::numeric,\n      refund_method = COALESCE(refund_method, $4),\n      refunded_reason = COALESCE(refunded_reason, $5),\n      refunded_by = COALESCE(refunded_by, NULLIF($6, \x27\x27)::uuid),\n      refund_payment_id = COALESCE(refund_payment_id, NULLIF($7, \x27\x27)::uuid),\n      updated_at = NOW()\n    WHERE id = $2::uuid\n      AND organization_id = $3::uuid\n      AND deleted_at IS NULL;\n    `,\n    [\n      args.amount,\n      args.purchaseId,\n      args.organizationId,\n      args.refundMethod,\n      args.reason,\n      args.refundedByUserId,\n      args.refundPaymentId,\n    ]\n  );\n}/s;
  }

  # Update calls to upsertRefundMilestones to pass audit args (do two passes safely)
  s/upsertRefundMilestones\(client,\s*\{\s*organizationId:\s*args\.organizationId,\s*purchaseId:\s*purchase\.id,\s*amount,[\s\S]*?\}\);/upsertRefundMilestones(client, {\n    organizationId: args.organizationId,\n    purchaseId: purchase.id,\n    amount,\n    refundMethod: args.refundMethod ?? null,\n    reason: args.reason ?? null,\n    refundedByUserId: args.refundedByUserId ?? null,\n    refundPaymentId: args.refundPaymentId ?? null,\n  });/sg;
' "$SVC"

echo "==> patching routes (valid perl)"

perl -0777 -i -pe '
  # Ensure refund Body supports reason/refundPaymentId (best-effort)
  if ($_ !~ /refundPaymentId/) {
    s/(refundMethod:\s*"card"\s*\|\s*"bank_transfer"\s*\|\s*"wallet";\s*amount\?:\s*number;)/$1 reason?: string; refundPaymentId?: string;/s;
  }

  # Ensure handler reads reason/refundPaymentId and passes refundMethod+audit args
  if ($_ !~ /const reason = request\.body\?\./) {
    s/(const refundMethod\s*=\s*request\.body\?\.\s*refundMethod;\s*)/$1\n    const reason = (request.body as any)?.reason ?? null;\n    const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;\n    const refundedByUserId = (request as any).user?.sub ?? (request as any).user?.id ?? null;\n/s;
  }

  # Ensure refundPropertyPurchase call includes audit fields
  if ($_ !~ /refundPaymentId,\s*refundedByUserId/s) {
    s/refundPropertyPurchase\(client,\s*\{\s*organizationId:\s*orgId,\s*purchaseId,\s*amount,\s*reason\s*\}\)/refundPropertyPurchase(client, {\n        organizationId: orgId,\n        purchaseId,\n        amount,\n        reason,\n        refundMethod,\n        refundPaymentId,\n        refundedByUserId,\n      })/s;
  }
' "$ROUTES"

echo "==> sanity checks"
grep -q "refund_method" "$SVC" || { echo "❌ service missing refund_method"; exit 1; }
grep -q "refundPaymentId" "$SVC" || { echo "❌ service missing refundPaymentId"; exit 1; }
grep -q "/purchases/:purchaseId/refund" "$ROUTES" || { echo "❌ routes missing refund endpoint"; exit 1; }

echo ""
echo "==> typecheck"
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit

echo ""
echo "✅ FIXED"
echo "NEXT:"
echo "  npm run dev"
