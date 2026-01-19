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

echo "==> 1) sanitize refundedBy/refundPaymentId (convert '' -> null) in upsertRefundMilestones() params array"

# Replace the args.refundedBy / args.refundPaymentId entries in the query param array with safe expressions.
perl -0777 -i -pe '
  s/\(\s*args\.refundedBy\s*\?\?\s*null\s*\)/((args.refundedBy && String(args.refundedBy).trim()) ? String(args.refundedBy).trim() : null)/g;
  s/\(\s*args\.refundPaymentId\s*\?\?\s*null\s*\)/((args.refundPaymentId && String(args.refundPaymentId).trim()) ? String(args.refundPaymentId).trim() : null)/g;
' "$FILE"

echo "==> 2) make SQL uuid casts safe (NULLIF(...,'''')::uuid) for refunded_by/refund_payment_id"

# Wherever refunded_by or refund_payment_id assigns $N::uuid, make it NULLIF($N::text,'')::uuid
perl -0777 -i -pe '
  s/(refunded_by\s*=\s*COALESCE\([^,]+,\s*)\$(\d+)::uuid\)/$1NULLIF(\$$2::text, \x27\x27)::uuid)/g;
  s/(refunded_by\s*=\s*)\$(\d+)::uuid/$1NULLIF(\$$2::text, \x27\x27)::uuid/g;

  s/(refund_payment_id\s*=\s*COALESCE\([^,]+,\s*)\$(\d+)::uuid\)/$1NULLIF(\$$2::text, \x27\x27)::uuid)/g;
  s/(refund_payment_id\s*=\s*)\$(\d+)::uuid/$1NULLIF(\$$2::text, \x27\x27)::uuid/g;
' "$FILE"

echo "==> 3) quick sanity: show any remaining refunded_by/refund_payment_id uuid casts"
echo "--- remaining refunded_by/refund_payment_id ::uuid casts (should be none) ---"
grep -nE 'refunded_by|refund_payment_id' "$FILE" | grep -n '::uuid' || true
echo "------------------------------------------------------------"

echo "==> 4) typecheck"
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit

echo ""
echo "✅ FIXED uuid empty-string casting in purchase_refunds.service.ts"
echo "NEXT:"
echo "  1) restart server: npm run dev"
echo "  2) re-login + refresh ORG_ID:"
echo "     eval \"\$(./scripts/login.sh)\""
echo "     export ORG_ID=\"\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r .data.organization_id)\""
echo "  3) call refund again:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
