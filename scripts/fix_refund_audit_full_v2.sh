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

export ROUTES SVC

python3 - <<'PY'
from pathlib import Path
import os, re

routes = Path(os.environ["ROUTES"])
svc = Path(os.environ["SVC"])

# ----------------------------
# PATCH ROUTES
# ----------------------------
t = routes.read_text(encoding="utf-8")

if "/purchases/:purchaseId/refund" not in t:
    raise SystemExit("❌ Refund route not found in purchases.routes.ts")

# Make Body type include optional audit fields (safe even if already updated)
t = re.sub(
    r'Body:\s*\{\s*refundMethod:\s*"card"\s*\|\s*"bank_transfer"\s*\|\s*"wallet";\s*amount\?:\s*number;\s*\}',
    'Body: { refundMethod: "card" | "bank_transfer" | "wallet"; amount?: number; reason?: string; refundPaymentId?: string; refundedBy?: string }',
    t,
    count=1
)

# Ensure extraction block exists and is correct (refundMethod + reason + refundPaymentId + refundedByUserId + amount)
# Anchor on: const refundMethod = request.body?.refundMethod;
anchor = r'const\s+refundMethod\s*=\s*request\.body\?\.\s*refundMethod\s*;'
extract_block = """const refundMethod = request.body?.refundMethod;

    // audit fields (optional)
    const reason = (request.body as any)?.reason ?? null;
    const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;

    // Prefer auth user id/sub; fallback to body.refundedBy if auth isn't wired yet
    const refundedByUserId =
      (request as any).user?.id ??
      (request as any).user?.sub ??
      (request.body as any)?.refundedBy ??
      null;

    const amount = request.body?.amount;"""

if re.search(anchor, t):
    t = re.sub(anchor, extract_block, t, count=1)
else:
    # If the anchor doesn't exist, we won't guess further (avoid breaking the file).
    raise SystemExit("❌ Could not find refundMethod line to patch in refund handler")

# Replace the refundPropertyPurchase call payload to map correctly
call_pat = r"""
const\s+result\s*=\s*await\s+refundPropertyPurchase\(\s*client\s*,\s*\{\s*
[\s\S]*?
\}\s*\)\s*;
"""
replacement = """const result = await refundPropertyPurchase(client, {
        organizationId: orgId,
        purchaseId,
        amount: typeof amount === "number" ? amount : undefined,

        // ✅ correct mapping
        refundMethod: refundMethod ?? null,
        reason: reason ?? null,
        refundPaymentId: refundPaymentId ?? null,
        refundedBy: refundedByUserId ?? null,
      });"""

t2 = re.sub(call_pat, replacement, t, count=1, flags=re.VERBOSE)
if t2 == t:
    raise SystemExit("❌ Could not find refundPropertyPurchase(client, { ... }) call to patch")

routes.write_text(t2, encoding="utf-8")
print("✅ routes patched:", routes)

# ----------------------------
# PATCH SERVICE
# ----------------------------
s = svc.read_text(encoding="utf-8")

# In upsertRefundMilestones SQL: overwrite audit fields if provided (and avoid uuid cast errors on '')
# We replace the audit block region by markers.
audit_block_pat = r"""
--\s*audit\s*fields[\s\S]*?
updated_at\s*=\s*NOW\(\)
"""
audit_block_new = """-- audit fields (overwrite if provided)
      refund_method = COALESCE(NULLIF($2::text, ''), refund_method),
      refunded_reason = COALESCE(NULLIF($3::text, ''), refunded_reason),
      refunded_by = COALESCE(NULLIF($4::text, '')::uuid, refunded_by),
      refund_payment_id = COALESCE(NULLIF($5::text, '')::uuid, refund_payment_id),

      updated_at = NOW()"""

s2 = re.sub(audit_block_pat, audit_block_new, s, count=1, flags=re.VERBOSE)
if s2 == s:
    raise SystemExit("❌ Could not find audit block in upsertRefundMilestones() to replace")

svc.write_text(s2, encoding="utf-8")
print("✅ service patched:", svc)
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

cat <<'NEXT'

NEXT:
1) restart server:
   npm run dev

2) set env + login:
   export API="http://127.0.0.1:4000"
   eval "$(./scripts/login.sh)"
   export ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
   export USER_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"

3) set purchase:
   export PURCHASE_ID="f72177d5-38ea-499f-86c7-8f4f1e063a02"

4) call refund again (idempotent) with refundedBy fallback:
   curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
     -H "content-type: application/json" \
     -H "authorization: Bearer $TOKEN" \
     -H "x-organization-id: $ORG_ID" \
     -d "{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\",\"refundedBy\":\"$USER_ID\"}" | jq

5) verify DB:
   PAGER=cat psql -d "$DB_NAME" -X -c "select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;"

NEXT
