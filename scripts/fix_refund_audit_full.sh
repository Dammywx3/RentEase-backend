#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTES="$ROOT/src/routes/purchases.routes.ts"
SVC="$ROOT/src/services/purchase_refunds.service.ts"

[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }
[ -f "$SVC" ] || { echo "❌ Not found: $SVC"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"

cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.$TS"
cp "$SVC"    "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
echo "✅ backups -> scripts/.bak/*.$TS"

python3 - <<PY
from pathlib import Path
import re

routes = Path(r"$ROUTES")
svc = Path(r"$SVC")

# ----------------------------
# 1) PATCH ROUTES
# ----------------------------
t = routes.read_text(encoding="utf-8")

# Ensure refund route exists
if "/purchases/:purchaseId/refund" not in t:
    raise SystemExit("❌ Could not find refund route '/purchases/:purchaseId/refund' in routes file")

# 1a) Expand Body type to allow optional audit fields (TS friendliness)
# Replace the refund route Body type block if it matches the old minimal one.
t2 = re.sub(
    r'Body:\s*\{\s*refundMethod:\s*"card"\s*\|\s*"bank_transfer"\s*\|\s*"wallet";\s*amount\?:\s*number;\s*\}',
    'Body: { refundMethod: "card" | "bank_transfer" | "wallet"; amount?: number; reason?: string; refundPaymentId?: string; refundedBy?: string }',
    t,
    count=1
)

# 1b) Ensure the handler extracts correct fields
# We'll keep your existing variables if present, but ensure we have:
# refundMethod, reason, refundPaymentId, refundedByUserId, amount
# and we pass correct mapping to service.

# Replace ONLY the object passed to refundPropertyPurchase(...) inside the refund handler.
pattern = r"""
const\s+result\s*=\s*await\s+refundPropertyPurchase\(\s*client\s*,\s*\{\s*
[\s\S]*?
\}\s*\)\s*;
"""
replacement = """const result = await refundPropertyPurchase(client, {
        organizationId: orgId,
        purchaseId,
        amount: typeof amount === "number" ? amount : undefined,

        // ✅ Correct mapping:
        refundMethod: refundMethod ?? null,
        reason: reason ?? null,
        refundPaymentId: refundPaymentId ?? null,
        refundedBy: refundedByUserId ?? null,
      });"""

t3 = re.sub(pattern, replacement, t2, count=1, flags=re.VERBOSE)

if t3 == t2:
    # If we failed to match, show a clearer error.
    raise SystemExit("❌ Could not find/replace the refundPropertyPurchase(client, { ... }) call in refund handler")

# 1c) Ensure we define the variables in the refund handler (without duplicating)
# We’ll insert/replace the extraction block right after refundMethod line.
# This is anchored to: const refundMethod = request.body?.refundMethod;
anchor = r'const\s+refundMethod\s*=\s*request\.body\?\.\s*refundMethod\s*;'
m = re.search(anchor, t3)
if not m:
    raise SystemExit("❌ Could not find 'const refundMethod = request.body?.refundMethod;' in refund handler")

# Build a safe extraction block
extract_block = """const refundMethod = request.body?.refundMethod;

    // audit fields (optional)
    const reason = (request.body as any)?.reason ?? null;
    const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;

    // Prefer auth user id/sub; if your auth doesn't populate request.user yet,
    // allow passing refundedBy explicitly from body for now.
    const refundedByUserId =
      (request as any).user?.id ??
      (request as any).user?.sub ??
      (request.body as any)?.refundedBy ??
      null;

    const amount = request.body?.amount;"""

# Replace the single line "const refundMethod = ..." with our block
t4 = re.sub(anchor, extract_block, t3, count=1)

routes.write_text(t4, encoding="utf-8")
print("✅ routes patched:", routes)

# ----------------------------
# 2) PATCH SERVICE
# ----------------------------
s = svc.read_text(encoding="utf-8")

# We patch the SQL inside upsertRefundMilestones so audit fields overwrite if provided
# and also protect uuid casts from empty strings using NULLIF(...,'')::uuid.
sql_old_pattern = r"""
--\s*audit\s*fields[\s\S]*?
updated_at\s*=\s*NOW\(\)
"""
sql_new_block = """-- audit fields (overwrite if provided)
      refund_method = COALESCE(NULLIF($2::text, ''), refund_method),
      refunded_reason = COALESCE(NULLIF($3::text, ''), refunded_reason),
      refunded_by = COALESCE(NULLIF($4::text, '')::uuid, refunded_by),
      refund_payment_id = COALESCE(NULLIF($5::text, '')::uuid, refund_payment_id),

      updated_at = NOW()"""

s2 = re.sub(sql_old_pattern, sql_new_block, s, count=1, flags=re.VERBOSE)

if s2 == s:
    raise SystemExit("❌ Could not find audit fields block in upsertRefundMilestones() SQL to replace")

svc.write_text(s2, encoding="utf-8")
print("✅ service patched:", svc)
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

cat <<'NEXT'

✅ DONE.

NEXT:
1) restart dev server:
   npm run dev

2) re-login / refresh env vars:
   export API="http://127.0.0.1:4000"
   eval "$(./scripts/login.sh)"
   export ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
   export USER_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"

3) set PURCHASE_ID:
   export PURCHASE_ID="f72177d5-38ea-499f-86c7-8f4f1e063a02"

4) call refund again (idempotent) with audit fields:
   curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
     -H "content-type: application/json" \
     -H "authorization: Bearer $TOKEN" \
     -H "x-organization-id: $ORG_ID" \
     -d "{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\",\"refundedBy\":\"$USER_ID\"}" | jq

5) verify DB:
   PAGER=cat psql -d "$DB_NAME" -X -c "select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;"

NOTE:
- If refunded_by is still NULL even after sending refundedBy in body, then the DB update is not being hit (service not called or different code path).
- If refunded_by works only when you pass refundedBy in body, then your auth middleware is not populating request.user for this route.

NEXT
