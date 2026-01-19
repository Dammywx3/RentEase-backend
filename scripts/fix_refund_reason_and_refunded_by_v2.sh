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
import os
from pathlib import Path

svc = Path(os.environ["SVC_PATH"])
routes = Path(os.environ["ROUTES_PATH"])

# -------------------------
# 1) Patch SERVICE: audit overwrite when new value provided
# -------------------------
t = svc.read_text(encoding="utf-8")

needle = "UPDATE public.property_purchases"
i = t.find(needle)
if i == -1:
    raise SystemExit("❌ service: could not find UPDATE public.property_purchases")

# Find the end of that UPDATE statement up to "deleted_at IS NULL;"
end_anchor = "AND deleted_at IS NULL;"
j = t.find(end_anchor, i)
if j == -1:
    raise SystemExit("❌ service: could not find end anchor 'AND deleted_at IS NULL;'")

# Expand to include the semicolon
j = t.find(";", j)
if j == -1:
    raise SystemExit("❌ service: could not find semicolon after update")
j += 1

new_update = """UPDATE public.property_purchases
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

t2 = t[:i] + new_update + t[j:]
svc.write_text(t2, encoding="utf-8")
print("✅ service patched (audit overwrite enabled)")

# -------------------------
# 2) Patch ROUTES: remove stray req-body lines at top (if present)
# -------------------------
r = routes.read_text(encoding="utf-8").splitlines(True)

clean = []
for line in r:
    # remove bad injected lines that reference req at top-level
    if line.lstrip().startswith("const body: any = req.body"):
        continue
    if line.lstrip().startswith("const refundMethod = body."):
        continue
    if line.lstrip().startswith("const reason = body."):
        continue
    if line.lstrip().startswith("const refundPaymentId = body."):
        continue
    if line.lstrip().startswith("const refundedBy = (req as any).user"):
        continue
    clean.append(line)

rtext = "".join(clean)

# -------------------------
# 3) Patch refund handler by locating the handler block, then replacing the refundPropertyPurchase args object
# -------------------------
target = '"/purchases/:purchaseId/refund"'
pos = rtext.find(target)
if pos == -1:
    raise SystemExit("❌ routes: could not find refund route path string")

# Find the start of handler block: first '{' after the route declaration
# We'll locate the opening brace of the async handler: 'async (request, reply) => {'
async_sig = "async (request, reply) => {"
k = rtext.find(async_sig, pos)
if k == -1:
    raise SystemExit("❌ routes: could not find async handler signature for refund route")

block_start = rtext.find("{", k)
if block_start == -1:
    raise SystemExit("❌ routes: could not find opening { for refund handler")

# Brace-count to find end of handler block
depth = 0
end = None
for idx in range(block_start, len(rtext)):
    ch = rtext[idx]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = idx + 1
            break
if end is None:
    raise SystemExit("❌ routes: could not find end of refund handler block by brace matching")

handler = rtext[block_start:end]

def ensure_line(handler_text: str, after_sub: str, line: str) -> str:
    if line in handler_text:
        return handler_text
    at = handler_text.find(after_sub)
    if at == -1:
        # if we can't find insertion point, put near top after orgId checks are done
        ins = handler_text.find("const { purchaseId }")
        if ins == -1:
            return handler_text
        nl = handler_text.find("\n", ins)
        return handler_text[:nl+1] + "    " + line + "\n" + handler_text[nl+1:]
    nl = handler_text.find("\n", at)
    return handler_text[:nl+1] + "    " + line + "\n" + handler_text[nl+1:]

# Ensure local vars exist INSIDE handler
handler = ensure_line(handler, "const { purchaseId }", 'const refundMethod = request.body?.refundMethod;')
handler = ensure_line(handler, "const refundMethod", 'const amount = request.body?.amount;')
handler = ensure_line(handler, "const amount", 'const reason = (request.body as any)?.reason ?? null;')
handler = ensure_line(handler, "const reason", 'const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;')
handler = ensure_line(handler, "const refundPaymentId", 'const refundedByUserId = (request as any).user?.id ?? (request as any).user?.sub ?? null;')

# Now locate refundPropertyPurchase call inside handler
call_key = "refundPropertyPurchase"
cp = handler.find(call_key)
if cp == -1:
    raise SystemExit("❌ routes: could not find refundPropertyPurchase call inside refund handler")

# Find the first "{...}" object literal passed to refundPropertyPurchase(client, { ... })
# We find the first "{" after the substring "refundPropertyPurchase"
brace_open = handler.find("{", cp)
if brace_open == -1:
    raise SystemExit("❌ routes: could not find object { after refundPropertyPurchase")

# Brace match this object
depth = 0
brace_close = None
for idx in range(brace_open, len(handler)):
    ch = handler[idx]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            brace_close = idx
            break
if brace_close is None:
    raise SystemExit("❌ routes: could not match closing } for refundPropertyPurchase args object")

new_obj = """{
        organizationId: orgId,
        purchaseId,
        amount: typeof amount === "number" ? amount : undefined,
        refundMethod: refundMethod,
        reason: reason,
        refundPaymentId: refundPaymentId,
        refundedBy: refundedByUserId,
      }"""

handler2 = handler[:brace_open] + new_obj + handler[brace_close+1:]

# Replace handler back into file
rtext2 = rtext[:block_start] + handler2 + rtext[end:]
routes.write_text(rtext2, encoding="utf-8")
print("✅ routes patched (reason/refundedBy mapping fixed + robust replace)")
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

echo ""
echo "NEXT:"
echo "  1) restart server: npm run dev"
echo "  2) re-login:"
echo "     export API=\"http://127.0.0.1:4000\""
echo "     eval \"\$(./scripts/login.sh)\""
echo "     export ORG_ID=\"\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r '.data.organization_id')\""
echo "  3) call refund again (idempotent):"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
echo "  4) verify DB:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
