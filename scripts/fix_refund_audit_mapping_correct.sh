#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/services/purchase_refunds.service.ts"

[ -f "$FILE" ] || { echo "❌ Not found: $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$FILE" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

# 1) Fix the UPDATE mapping inside upsertRefundMilestones:
#    refund_method   <- args.refundMethod
#    refunded_reason <- args.reason
#    refunded_by     <- args.refundedBy
#    refund_payment_id <- args.refundPaymentId
perl -0777 -i -pe '
  s/refund_method\s*=\s*COALESCE\(refund_method,\s*\$2::text\),/refund_method = COALESCE(refund_method, $2::text),/g;
  s/refunded_reason\s*=\s*COALESCE\(refunded_reason,\s*\$3::text\),/refunded_reason = COALESCE(refunded_reason, $3::text),/g;
  s/refunded_by\s*=\s*COALESCE\(refunded_by,\s*\$4::uuid\),/refunded_by = COALESCE(refunded_by, $4::uuid),/g;
  s/refund_payment_id\s*=\s*COALESCE\(refund_payment_id,\s*\$5::uuid\),/refund_payment_id = COALESCE(refund_payment_id, $5::uuid),/g;
' "$FILE"

# 2) Ensure the args array order matches those placeholders:
#    [$1 amount, $2 refundMethod, $3 reason, $4 refundedBy, $5 refundPaymentId, $6 purchaseId, $7 organizationId]
perl -0777 -i -pe '
  s/\[\s*args\.amount,\s*\(args\.refundMethod\s*\?\?\s*null\),\s*\(args\.reason\s*\?\?\s*null\),\s*\(args\.refundedBy\s*\?\?\s*null\),\s*\(args\.refundPaymentId\s*\?\?\s*null\),\s*args\.purchaseId,\s*args\.organizationId\s*\]/[
      args.amount,
      (args.refundMethod ?? null),
      (args.reason ?? null),
      (args.refundedBy ?? null),
      (args.refundPaymentId ?? null),
      args.purchaseId,
      args.organizationId,
    ]/sg;
' "$FILE"

# 3) In idempotent blocks, fix the call so "reason" maps correctly and "lastPaymentId" is always passed.
#    This just ensures the object contains lastPaymentId.
perl -0777 -i -pe '
  s/(upsertRefundMilestones\(client,\s*\{\s*\n\s*organizationId:\s*args\.organizationId,\s*\n\s*purchaseId:\s*purchase\.id,\s*\n\s*amount:\s*0,\s*\n)(?!\s*lastPaymentId:)/$1  lastPaymentId: purchase.last_payment_id ?? null,\n/smg;
' "$FILE"

# 4) Sanity checks: make sure mapping keywords exist
grep -q "refund_method = COALESCE(refund_method, \\$2::text)" "$FILE" || { echo "❌ missing refund_method mapping"; exit 1; }
grep -q "refunded_reason = COALESCE(refunded_reason, \\$3::text)" "$FILE" || { echo "❌ missing refunded_reason mapping"; exit 1; }
grep -q "refunded_by = COALESCE(refunded_by, \\$4::uuid)" "$FILE" || { echo "❌ missing refunded_by mapping"; exit 1; }
grep -q "refund_payment_id = COALESCE(refund_payment_id, \\$5::uuid)" "$FILE" || { echo "❌ missing refund_payment_id mapping"; exit 1; }

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit

echo "✅ FIXED mapping in: $FILE"
echo ""
echo "NEXT:"
echo "  1) restart dev server: npm run dev"
echo "  2) re-login:"
echo "     eval \"\$(./scripts/login.sh)\""
echo "     export ORG_ID=\"\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r .data.organization_id)\""
echo "  3) set PURCHASE_ID (yours got empty before):"
echo "     export PURCHASE_ID=\"\$(psql -d \"\$DB_NAME\" -Atc \"select id from public.property_purchases where deleted_at is null order by created_at desc limit 1;\" | tr -d \"[:space:]\")\""
echo "  4) call refund again (idempotent; should fill audit fields):"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" -H \"content-type: application/json\" -H \"authorization: Bearer \$TOKEN\" -H \"x-organization-id: \$ORG_ID\" -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
echo "  5) verify DB:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
