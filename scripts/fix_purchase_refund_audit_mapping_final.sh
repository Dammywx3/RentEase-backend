#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC="$ROOT/src/services/purchase_refunds.service.ts"

[ -f "$SVC" ] || { echo "❌ Not found: $SVC"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$SVC" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_refunds.service.ts.bak.$TS"

python3 - <<PY
from pathlib import Path
import re

p = Path(r"$SVC")
s = p.read_text(encoding="utf-8")

# --- helpers to avoid "" for uuid columns ---
if "function cleanUuid" not in s:
    # insert helper near top (after imports)
    s = re.sub(
        r'^(import[^\n]*\n(?:import[^\n]*\n)*)',
        r'\\1\\nfunction cleanUuid(v: any): string | null {\\n  if (v === null || v === undefined) return null;\\n  const t = String(v).trim();\\n  return t.length ? t : null;\\n}\\n\\nfunction cleanText(v: any): string | null {\\n  if (v === null || v === undefined) return null;\\n  const t = String(v).trim();\\n  return t.length ? t : null;\\n}\\n',
        s,
        count=1,
        flags=re.M
    )

# --- Patch upsertRefundMilestones to: 
# 1) accept userId (refundedBy) and paymentId safely
# 2) set refund_method and refunded_reason correctly
# 3) allow correcting wrong values on idempotent calls:
#    - if refund_method is NULL -> set it
#    - if refunded_reason is NULL or equals refund_method (bad old bug) -> replace with provided reason
#    - if refund_payment_id is NULL -> set it
#    - if refunded_by is NULL -> set it
#
# We'll replace the whole function body by anchor match.
pat = re.compile(r"async function upsertRefundMilestones\\s*\\([\\s\\S]*?\\n\\}\\n", re.M)
m = pat.search(s)
if not m:
    raise SystemExit("❌ Could not find upsertRefundMilestones() to patch")

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
  const refundMethod = cleanText(args.refundMethod);
  const reason = cleanText(args.reason);
  const refundedBy = cleanUuid(args.refundedBy);
  const refundPaymentId = cleanUuid(args.refundPaymentId);

  await client.query(
    `
    UPDATE public.property_purchases
    SET
      payment_status = 'refunded'::purchase_payment_status,
      refunded_at = COALESCE(refunded_at, NOW()),
      refunded_amount = COALESCE(refunded_amount, 0) + $1::numeric,

      -- audit fields:
      -- 1) set refund_method if empty
      refund_method = COALESCE(refund_method, $2::text),

      -- 2) set/repair refunded_reason:
      --    if it's NULL OR equals refund_method (old bug), replace with provided reason
      refunded_reason = CASE
        WHEN $3::text IS NULL THEN refunded_reason
        WHEN refunded_reason IS NULL THEN $3::text
        WHEN refund_method IS NOT NULL AND refunded_reason = refund_method THEN $3::text
        ELSE refunded_reason
      END,

      -- 3) set refunded_by if empty
      refunded_by = COALESCE(refunded_by, $4::uuid),

      -- 4) set refund_payment_id if empty
      refund_payment_id = COALESCE(refund_payment_id, $5::uuid),

      updated_at = NOW()
    WHERE id = $6::uuid
      AND organization_id = $7::uuid
      AND deleted_at IS NULL;
    `,
    [
      args.amount,
      refundMethod,
      reason,
      refundedBy,
      refundPaymentId,
      args.purchaseId,
      args.organizationId,
    ]
  );
}
"""
s = s[:m.start()] + replacement + s[m.end():]

# --- Ensure ALL calls to upsertRefundMilestones include lastPaymentId (TS errors earlier)
# If any call omits it, add it using purchase.last_payment_id ?? null when purchase is in scope.
# We'll do a small conservative patch: in object literals passed to upsertRefundMilestones, if lastPaymentId missing but purchase.last_payment_id exists nearby.
def add_last_payment_id(block: str) -> str:
    if "lastPaymentId:" in block:
        return block
    # Insert after amount: ...
    block = re.sub(r"(\\n\\s*amount\\s*:\\s*[^,\\n]+,)",
                   r"\\1\\n      lastPaymentId: purchase.last_payment_id ?? null,",
                   block, count=1)
    return block

# Patch common patterns upsertRefundMilestones(client, { ... });
call_pat = re.compile(r"upsertRefundMilestones\\(client,\\s*\\{[\\s\\S]*?\\}\\);", re.M)
def repl_call(mm):
    blk = mm.group(0)
    return add_last_payment_id(blk)

s2 = call_pat.sub(repl_call, s)
s = s2

p.write_text(s, encoding="utf-8")
print("✅ service patched:", p)
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

cat <<'NEXT'

✅ DONE.

NEXT:
1) restart dev server:
   npm run dev

2) re-login + export vars:
   export API="http://127.0.0.1:4000"
   eval "$(./scripts/login.sh)"
   export ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
   export USER_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"

3) set PURCHASE_ID:
   export PURCHASE_ID="f72177d5-38ea-499f-86c7-8f4f1e063a02"

4) call refund again (idempotent) WITH refundedBy:
   curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
     -H "content-type: application/json" \
     -H "authorization: Bearer $TOKEN" \
     -H "x-organization-id: $ORG_ID" \
     -d "{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\",\"refundedBy\":\"$USER_ID\"}" | jq

5) verify DB (should now be filled, reason should be buyer cancelled):
   PAGER=cat psql -d "$DB_NAME" -X -c "select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;"

NEXT
