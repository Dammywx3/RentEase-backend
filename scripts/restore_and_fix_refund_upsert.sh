#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$ROOT/src/services/purchase_refunds.service.ts"
BAK_DIR="$ROOT/scripts/.bak"

[ -f "$FILE" ] || { echo "❌ Not found: $FILE"; exit 1; }
mkdir -p "$BAK_DIR"

# 1) restore latest backup to recover from any "red file" damage
LATEST_BAK="$(ls -t "$BAK_DIR"/purchase_refunds.service.ts.bak.* 2>/dev/null | head -n 1 || true)"
if [ -z "${LATEST_BAK:-}" ]; then
  echo "❌ No backups found in $BAK_DIR (purchase_refunds.service.ts.bak.*)"
  exit 1
fi

cp "$LATEST_BAK" "$FILE"
echo "✅ restored latest backup: $LATEST_BAK -> $FILE"

# 2) make a new backup of the restored state
TS="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "$BAK_DIR/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

# 3) Replace ONLY upsertRefundMilestones() by anchoring until insertDebitTxn()
perl -0777 -i -pe '
  my $replacement = q{
async function upsertRefundMilestones(
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
      payment_status = \x27refunded\x27::purchase_payment_status,
      refunded_at = COALESCE(refunded_at, NOW()),
      refunded_amount = COALESCE(refunded_amount, 0) + $1::numeric,

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

};
  s#async function upsertRefundMilestones\s*\([\s\S]*?\n\}\n\n(?=async function insertDebitTxn)#${replacement}\n\n#sm
    or die "PATCH_FAIL: could not find upsertRefundMilestones() block anchored before insertDebitTxn()";
' "$FILE"

# 4) Sanity checks (mapping correctness)
grep -q 'refund_method = COALESCE(refund_method, \$2::text)' "$FILE" || { echo "❌ missing refund_method mapping"; exit 1; }
grep -q 'refunded_reason = COALESCE(refunded_reason, \$3::text)' "$FILE" || { echo "❌ missing refunded_reason mapping"; exit 1; }
grep -q 'refunded_by = COALESCE(refunded_by, \$4::uuid)' "$FILE" || { echo "❌ missing refunded_by mapping"; exit 1; }
grep -q 'refund_payment_id = COALESCE(refund_payment_id, \$5::uuid)' "$FILE" || { echo "❌ missing refund_payment_id mapping"; exit 1; }

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ FIXED: $FILE"

echo ""
echo "NEXT:"
echo "  1) restart server: npm run dev"
echo "  2) re-login + refresh ORG_ID + PURCHASE_ID:"
echo "     eval \"\$(./scripts/login.sh)\""
echo "     export ORG_ID=\"\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r .data.organization_id)\""
echo "     export PURCHASE_ID=\"\${PURCHASE_ID:-\$(psql -d \"\$DB_NAME\" -Atc \"select id from public.property_purchases where deleted_at is null order by created_at desc limit 1;\" | tr -d \"[:space:]\")}\""
echo "  3) call refund (idempotent) with audit fields:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
echo "  4) verify DB:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
