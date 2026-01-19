#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/services/purchase_refunds.service.ts"

[ -f "$FILE" ] || { echo "❌ Not found: $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$FILE" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

# Replace the whole upsertRefundMilestones() function with a known-good version:
# - refund_method <= refundMethod
# - refunded_reason <= reason
# - refunded_by <= refundedBy (uuid)
# - refund_payment_id <= refundPaymentId (uuid)
# - amount=0 does NOT overwrite refunded_amount from NULL->0
perl -0777 -i -pe '
  s/async function upsertRefundMilestones\s*\([\s\S]*?\n\}\n\n/async function upsertRefundMilestones(\n  client: PoolClient,\n  args: {\n    organizationId: string;\n    purchaseId: string;\n    amount: number;\n    lastPaymentId: string | null;\n\n    refundMethod?: string | null;\n    reason?: string | null;\n    refundedBy?: string | null;\n    refundPaymentId?: string | null;\n  }\n) {\n  await client.query(\n    `\n    UPDATE public.property_purchases\n    SET\n      payment_status = \x27refunded\x27::purchase_payment_status,\n      refunded_at = COALESCE(refunded_at, NOW()),\n      refunded_amount = CASE\n        WHEN $1::numeric = 0 THEN refunded_amount\n        ELSE COALESCE(refunded_amount, 0) + $1::numeric\n      END,\n\n      -- audit fields (only fill if empty)\n      refund_method = COALESCE(refund_method, $2::text),\n      refunded_reason = COALESCE(refunded_reason, $3::text),\n      refunded_by = COALESCE(refunded_by, $4::uuid),\n      refund_payment_id = COALESCE(refund_payment_id, $5::uuid),\n\n      updated_at = NOW()\n    WHERE id = $6::uuid\n      AND organization_id = $7::uuid\n      AND deleted_at IS NULL;\n    `,\n    [\n      args.amount,\n      (args.refundMethod ?? null),\n      (args.reason ?? null),\n      (args.refundedBy ?? null),\n      (args.refundPaymentId ?? null),\n      args.purchaseId,\n      args.organizationId,\n    ]\n  );\n}\n\n/smg;
' "$FILE"

# Sanity checks using REGEX (whitespace-safe) so it won't false-fail
grep -nE 'async function upsertRefundMilestones' "$FILE" >/dev/null || { echo "❌ upsertRefundMilestones not found after patch"; exit 1; }
grep -Eq 'refund_method\s*=\s*COALESCE\(refund_method,\s*\$2::text\)' "$FILE" || { echo "❌ refund_method mapping still missing"; exit 1; }
grep -Eq 'refunded_reason\s*=\s*COALESCE\(refunded_reason,\s*\$3::text\)' "$FILE" || { echo "❌ refunded_reason mapping still missing"; exit 1; }

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ FIXED: $FILE"

echo ""
echo "NEXT:"
echo "  1) restart dev server: npm run dev"
echo "  2) re-login:"
echo "     eval \"\$(./scripts/login.sh)\""
echo "     export ORG_ID=\"\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r .data.organization_id)\""
echo "  3) ensure PURCHASE_ID is set:"
echo "     export PURCHASE_ID=\"\${PURCHASE_ID:-\$(psql -d \"\$DB_NAME\" -Atc \"select id from public.property_purchases where deleted_at is null order by created_at desc limit 1;\" | tr -d \"[:space:]\")}\""
echo "  4) call refund again:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" -H \"content-type: application/json\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
echo "  5) verify DB:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
