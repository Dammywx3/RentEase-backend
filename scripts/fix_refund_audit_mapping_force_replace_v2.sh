#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/services/purchase_refunds.service.ts"

[ -f "$FILE" ] || { echo "❌ Not found: $FILE"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$FILE" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

python3 - <<'PY'
from pathlib import Path
import sys, re

root = Path(__file__).resolve().parent.parent
file = root / "src/services/purchase_refunds.service.ts"
s = file.read_text(encoding="utf-8")

start_pat = r"async function upsertRefundMilestones\s*\("
end_pat   = r"async function insertDebitTxn\s*\("

m1 = re.search(start_pat, s)
m2 = re.search(end_pat, s)

if not m1 or not m2 or m2.start() <= m1.start():
    print("❌ Could not find anchors to replace block.")
    print("   Looking for:")
    print("    - async function upsertRefundMilestones(")
    print("    - async function insertDebitTxn(")
    print("")
    # show hints
    for needle in ["upsertRefundMilestones", "insertDebitTxn"]:
        idx = s.find(needle)
        print(f"   First occurrence of '{needle}':", idx)
    sys.exit(1)

replacement = """async function upsertRefundMilestones(
  client: PoolClient,
  args: {
    organizationId: string;
    purchaseId: string;
    amount: number;
    lastPaymentId: string | null;

    refundMethod?: string | null;
    reason?: string | null;
    refundedBy?: string | null;
    refundPaymentId?: string | null;
  }
) {
  await client.query(
    `
    UPDATE public.property_purchases
    SET
      payment_status = 'refunded'::purchase_payment_status,
      refunded_at = COALESCE(refunded_at, NOW()),
      refunded_amount = CASE
        WHEN $1::numeric = 0 THEN refunded_amount
        ELSE COALESCE(refunded_amount, 0) + $1::numeric
      END,

      -- audit fields (only fill if empty)
      refund_method = COALESCE(refund_method, $2::text),
      refunded_reason = COALESCE(refunded_reason, $3::text),
      refunded_by = COALESCE(refunded_by, $4::uuid),
      refund_payment_id = COALESCE(refund_payment_id, $5::uuid),

      updated_at = NOW()
    WHERE id = $6::uuid
      AND organization_id = $7::uuid
      AND deleted_at IS NULL;
    `,
    [
      args.amount,
      (args.refundMethod ?? null),
      (args.reason ?? null),
      (args.refundedBy ?? null),
      (args.refundPaymentId ?? null),
      args.purchaseId,
      args.organizationId,
    ]
  );
}

"""

new_s = s[:m1.start()] + replacement + s[m2.start():]
file.write_text(new_s, encoding="utf-8")
print("✅ Replaced upsertRefundMilestones() block by anchors.")
PY

# Sanity checks (whitespace tolerant)
grep -Eq "refund_method[[:space:]]*=[[:space:]]*COALESCE\\(refund_method,[[:space:]]*\\$2::text\\)" "$FILE" || {
  echo "❌ Still missing refund_method mapping after patch."
  echo "   Showing the upsertRefundMilestones block for debugging:"
  awk 'BEGIN{p=0} /async function upsertRefundMilestones/{p=1} p{print} /async function insertDebitTxn/{exit}' "$FILE" | sed -n '1,180p'
  exit 1
}

grep -Eq "refunded_reason[[:space:]]*=[[:space:]]*COALESCE\\(refunded_reason,[[:space:]]*\\$3::text\\)" "$FILE" || {
  echo "❌ Still missing refunded_reason mapping after patch."
  exit 1
}

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ FIXED: $FILE"

echo ""
echo "NEXT:"
echo "  1) restart server: npm run dev"
echo "  2) re-login:"
echo "     eval \"\$(./scripts/login.sh)\""
echo "     export ORG_ID=\"\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r .data.organization_id)\""
echo "  3) set PURCHASE_ID (if empty):"
echo "     export PURCHASE_ID=\"\${PURCHASE_ID:-\$(psql -d \"\$DB_NAME\" -Atc \"select id from public.property_purchases where deleted_at is null order by created_at desc limit 1;\" | tr -d \"[:space:]\")}\""
echo "  4) call refund again (idempotent):"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
echo "  5) verify DB:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
