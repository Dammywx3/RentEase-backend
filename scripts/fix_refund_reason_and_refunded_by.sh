#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC="$ROOT/src/services/purchase_refunds.service.ts"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$SVC" ] || { echo "❌ Not found: $SVC"; exit 1; }
[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$SVC"    "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.$TS"
echo "✅ backups -> scripts/.bak/*.$TS"

SVC_PATH="$SVC" ROUTES_PATH="$ROUTES" python3 - <<'PY'
import os, re
from pathlib import Path

svc = Path(os.environ["SVC_PATH"])
routes = Path(os.environ["ROUTES_PATH"])

# -------------------------
# 1) Patch SERVICE: allow audit overwrites on idempotent re-calls
# -------------------------
t = svc.read_text(encoding="utf-8")

# Replace only the UPDATE block inside upsertRefundMilestones (keep function signature & params array)
# We anchor on "UPDATE public.property_purchases" and the ending "deleted_at IS NULL;"
update_pat = re.compile(
    r"UPDATE public\.property_purchases\s*"
    r"SET\s*([\s\S]*?)\s*"
    r"WHERE id = \$6::uuid\s*"
    r"AND organization_id = \$7::uuid\s*"
    r"AND deleted_at IS NULL;",
    re.M
)

m = update_pat.search(t)
if not m:
    raise SystemExit("❌ Could not find upsertRefundMilestones UPDATE block in service")

new_update = r"""UPDATE public.property_purchases
    SET
      payment_status = 'refunded'::purchase_payment_status,
      refunded_at = COALESCE(refunded_at, NOW()),
      refunded_amount = COALESCE(refunded_amount, 0) + $1::numeric,

      -- audit fields: overwrite only if caller provided a non-null value
      refund_method = CASE WHEN $2::text IS NOT NULL THEN $2::text ELSE refund_method END,
      refunded_reason = CASE WHEN $3::text IS NOT NULL THEN $3::text ELSE refunded_reason END,
      refunded_by = CASE WHEN $4::uuid IS NOT NULL THEN $4::uuid ELSE refunded_by END,
      refund_payment_id = CASE WHEN $5::uuid IS NOT NULL THEN $5::uuid ELSE refund_payment_id END,

      updated_at = NOW()
    WHERE id = $6::uuid
      AND organization_id = $7::uuid
      AND deleted_at IS NULL;"""

t2 = t[:m.start()] + new_update + t[m.end():]
svc.write_text(t2, encoding="utf-8")
print("✅ service patched (audit overwrite enabled)")

# -------------------------
# 2) Patch ROUTE: ensure body.reason -> service reason, and refundedBy uses request.user id/sub
# -------------------------
r = routes.read_text(encoding="utf-8")

# Find refund route handler service call object and force correct fields.
# We only replace the object inside refundPropertyPurchase(client, { ... })
call_pat = re.compile(
    r"(refundPropertyPurchase\s*\(\s*client\s*,\s*\{)([\s\S]*?)(\}\s*\)\s*;)",
    re.M
)

# We only want the one inside "/purchases/:purchaseId/refund" handler.
# So locate that handler region first, then patch within it.
handler_pat = re.compile(
    r'("/purchases/:purchaseId/refund"[\s\S]*?\{\s*\n)([\s\S]*?)(\n\s*\}\);\s*)',
    re.M
)

hm = handler_pat.search(r)
if not hm:
    raise SystemExit("❌ Could not locate refund route handler block in purchases.routes.ts")

h_head, h_body, h_tail = hm.group(1), hm.group(2), hm.group(3)

# Ensure locals exist INSIDE the handler
def ensure(src: str, needle: str, line: str) -> str:
    if needle in src:
        return src
    ins_at = src.find("const { purchaseId }")
    if ins_at != -1:
        nl = src.find("\n", ins_at)
        return src[:nl+1] + "    " + line + "\n" + src[nl+1:]
    return "    " + line + "\n" + src

h_body = ensure(h_body, "const refundMethod", 'const refundMethod = request.body?.refundMethod;')
h_body = ensure(h_body, "const amount", 'const amount = request.body?.amount;')
h_body = ensure(h_body, "const reason", 'const reason = (request.body as any)?.reason ?? null;')
h_body = ensure(h_body, "const refundPaymentId", 'const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;')
h_body = ensure(h_body, "const refundedByUserId", 'const refundedByUserId = (request as any).user?.id ?? (request as any).user?.sub ?? null;')

cm = call_pat.search(h_body)
if not cm:
    raise SystemExit("❌ Could not find refundPropertyPurchase(client, { ... }) call inside refund handler")

new_obj = """
        organizationId: orgId,
        purchaseId,
        amount: typeof amount === "number" ? amount : undefined,
        refundMethod: refundMethod,
        reason: reason,
        refundPaymentId: refundPaymentId,
        refundedBy: refundedByUserId,
""".rstrip()

h_body2 = h_body[:cm.start(2)] + new_obj + h_body[cm.end(2):]
r2 = r[:hm.start()] + h_head + h_body2 + h_tail + r[hm.end():]
routes.write_text(r2, encoding="utf-8")
print("✅ routes patched (reason/refundedBy mapping forced)")
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

echo ""
echo "NEXT:"
echo "  1) restart server: npm run dev"
echo "  2) call refund again (idempotent):"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
echo "  3) verify DB:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
