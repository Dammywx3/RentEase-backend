#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVC="$ROOT/src/services/purchase_refunds.service.ts"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

ts="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"

backup() {
  local f="$1"
  cp "$f" "$ROOT/scripts/.bak/$(basename "$f").bak.$ts"
  echo "✅ backup: $f -> scripts/.bak/$(basename "$f").bak.$ts"
}

[ -f "$SVC" ] || { echo "❌ Missing: $SVC"; exit 1; }
[ -f "$ROUTES" ] || { echo "❌ Missing: $ROUTES"; exit 1; }

backup "$SVC"
backup "$ROUTES"

echo "==> patching service UUID casts to tolerate empty string"

# Replace $4::uuid and $5::uuid casts with NULLIF($x::text,'')::uuid
perl -0777 -i -pe '
  s/refunded_by\s*=\s*COALESCE\(refunded_by,\s*\$4::uuid\)/refunded_by = COALESCE(refunded_by, NULLIF(\$4::text, \x27\x27)::uuid)/g;
  s/refund_payment_id\s*=\s*COALESCE\(refund_payment_id,\s*\$5::uuid\)/refund_payment_id = COALESCE(refund_payment_id, NULLIF(\$5::text, \x27\x27)::uuid)/g;
' "$SVC"

# Sanity: make sure we now have NULLIF(... )::uuid in file
grep -q "NULLIF(\\$4::text, '')::uuid" "$SVC" || { echo "❌ Service patch failed for refunded_by"; exit 1; }
grep -q "NULLIF(\\$5::text, '')::uuid" "$SVC" || { echo "❌ Service patch failed for refund_payment_id"; exit 1; }

echo "==> patching route to pass null (not empty string) for refundPaymentId"

# This patch targets the refund handler call block and makes refundPaymentId safe.
# If your file already passes null correctly, this will be a no-op.
perl -0777 -i -pe '
  s/refundPaymentId:\s*String\(([^)]*?)\|\|\s*""\)/refundPaymentId: ($1 ? String($1) : null)/g;
  s/refundPaymentId:\s*String\(([^)]*?)\|\|\s*\x27\x27\)/refundPaymentId: ($1 ? String($1) : null)/g;
  s/refundPaymentId:\s*String\(([^)]*?)\)/refundPaymentId: ($1 ? String($1) : null)/g
    unless /refundPaymentId:\s*\([^)]*\?\s*String\(/s;
' "$ROUTES"

echo "==> typecheck"
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit

echo ""
echo "✅ FIXED"
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
