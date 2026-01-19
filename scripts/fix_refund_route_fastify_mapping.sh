#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchases.routes.ts.bak.$TS"

ROUTES_PATH="$ROUTES" python3 - <<'PY'
import os, re
from pathlib import Path

p = Path(os.environ["ROUTES_PATH"])
t = p.read_text(encoding="utf-8")

# 1) Remove the bad top-level injected lines that reference `req`
bad_block = re.compile(
    r"\n\s*const body: any = req\.body \?\? \{\};\n"
    r"\s*const refundMethod = body\.refundMethod \?\? null;\n"
    r"\s*const reason = body\.reason \?\? null;\n"
    r"\s*const refundPaymentId = body\.refundPaymentId \?\? null;\n"
    r"\s*const refundedBy = \(req as any\)\.user\?\.\w+\s*\?\?\s*null;\n",
    re.M
)
t2, n = bad_block.subn("\n", t)
t = t2

# 2) Patch ONLY the refund route handler mapping + service args
#    We will rewrite the refundPropertyPurchase call object to correct fields.
#    Also ensure we use reason from body, not refundMethod.
refund_route_pat = re.compile(
    r"(fastify\.post<\{\s*"
    r"Params:\s*\{\s*purchaseId:\s*string\s*\};\s*"
    r"Body:\s*\{[\s\S]*?\}\s*;\s*"
    r"\}>\(\s*\"/purchases/:purchaseId/refund\",\s*async\s*\(request,\s*reply\)\s*=>\s*\{)"
    r"([\s\S]*?)"
    r"(\n\s*\}\);\s*\n\}\s*\n?$)",
    re.M
)

m = refund_route_pat.search(t)
if not m:
    raise SystemExit("❌ Could not locate the refund route block. (Pattern mismatch)")

head, body, tail = m.group(1), m.group(2), m.group(3)

# Make sure these locals exist inside the handler
# We'll standardize the local extraction area.
# Find purchaseId line and replace a chunk after it up to amount assignment.
# If that gets too hard, we just ensure the key lines exist (idempotent inserts).
def ensure_line(src: str, needle: str, line: str) -> str:
    if needle in src:
        return src
    # insert after purchaseId extraction if possible
    pos = src.find("const { purchaseId }")
    if pos != -1:
        ins = src.find("\n", pos)
        return src[:ins+1] + line + "\n" + src[ins+1:]
    return line + "\n" + src

body = ensure_line(body, "const refundMethod", "    const refundMethod = request.body?.refundMethod;")
body = ensure_line(body, "const amount", "    const amount = request.body?.amount;")
body = ensure_line(body, "const reason =", "    const reason = (request.body as any)?.reason ?? null;")
body = ensure_line(body, "const refundPaymentId", "    const refundPaymentId = (request.body as any)?.refundPaymentId ?? null;")
body = ensure_line(body, "const refundedByUserId", "    const refundedByUserId = (request as any).user?.sub ?? (request as any).user?.id ?? null;")

# Now fix the service call block:
# Replace any existing refundPropertyPurchase(client, { ... }) object with correct mapping.
call_pat = re.compile(r"refundPropertyPurchase\s*\(\s*client\s*,\s*\{([\s\S]*?)\}\s*\)\s*;", re.M)
mc = call_pat.search(body)
if not mc:
    raise SystemExit("❌ Could not find refundPropertyPurchase(client, { ... }) call inside the refund route.")

new_obj = """
        organizationId: orgId,
        purchaseId,
        amount: typeof amount === "number" ? amount : undefined,
        refundMethod: refundMethod,
        reason: reason,
        refundPaymentId: refundPaymentId,
        refundedBy: refundedByUserId,
""".rstrip()

body = body[:mc.start(1)] + new_obj + body[mc.end(1):]

# Also fix the outdated comment that says "map refundMethod -> reason"
body = body.replace(
    "// NOTE: service currently expects { reason?: string }, so we map refundMethod -> reason",
    "// NOTE: refundMethod is the payment rail; reason is the human reason for the refund."
)

# Also fix any leftover "reason: refundMethod" lines if present
body = re.sub(r"\breason\s*:\s*refundMethod\s*,?", "reason: reason,", body)

# Ensure refundedBy uses the correct variable name
body = re.sub(r"\brefundedBy\s*:\s*refundedBy\b", "refundedBy: refundedByUserId", body)

t_fixed = t[:m.start()] + head + body + tail
p.write_text(t_fixed, encoding="utf-8")
print("✅ refund route fixed + top-level req lines removed")
PY

echo "🔎 Typecheck..."
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK: routes compile"

echo ""
echo "NEXT:"
echo "  1) restart server: npm run dev"
echo "  2) call refund again:"
echo "     curl -sS -X POST \"\$API/v1/purchases/\$PURCHASE_ID/refund\" \\"
echo "       -H \"content-type: application/json\" \\"
echo "       -H \"authorization: Bearer \$TOKEN\" \\"
echo "       -H \"x-organization-id: \$ORG_ID\" \\"
echo "       -d '{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\"}' | jq"
echo "  3) verify DB:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
