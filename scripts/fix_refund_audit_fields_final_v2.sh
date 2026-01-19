#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SVC="$ROOT/src/services/purchase_refunds.service.ts"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$SVC" ] || { echo "❌ Not found: $SVC"; exit 1; }
[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$SVC" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.$TS"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.$TS"
echo "✅ backups -> scripts/.bak/*.$TS"

echo "==> Patch service: purchase_refunds.service.ts (fix audit logic + allow correction on idempotent)"
python3 - "$SVC" <<'PY'
import sys, re
from pathlib import Path

svc_path = Path(sys.argv[1])
s = svc_path.read_text(encoding="utf-8")

fn_pos = s.find("async function upsertRefundMilestones")
if fn_pos == -1:
    raise SystemExit("❌ Could not find upsertRefundMilestones()")

block = s[fn_pos:]

m = re.search(r"await client\.query\(\s*`([\s\S]*?)`\s*,\s*\[", block)
if not m:
    raise SystemExit("❌ Could not locate SQL template backticks inside upsertRefundMilestones()")

sql = m.group(1)

needed = ["refund_method", "refunded_reason", "refunded_by", "refund_payment_id"]
if not all(k in sql for k in needed):
    raise SystemExit("❌ upsertRefundMilestones SQL missing expected audit columns")

# refund_method: fill if empty (good)
sql = re.sub(
    r"\n\s*refund_method\s*=\s*COALESCE\([^\n]*\),",
    "\n      refund_method = COALESCE(refund_method, $2::text),",
    sql,
)

# refunded_reason: fix bad historic value like 'card'/'wallet' by allowing overwrite when new reason is real text
sql = re.sub(
    r"\n\s*refunded_reason\s*=\s*COALESCE\([^\n]*\),",
    "\n      refunded_reason = CASE\n"
    "        WHEN refunded_reason IS NULL THEN $3::text\n"
    "        WHEN refunded_reason IN ('card','bank_transfer','wallet')\n"
    "             AND $3::text IS NOT NULL\n"
    "             AND $3::text NOT IN ('card','bank_transfer','wallet') THEN $3::text\n"
    "        ELSE refunded_reason\n"
    "      END,",
    sql,
)

sql = re.sub(
    r"\n\s*refunded_by\s*=\s*COALESCE\([^\n]*\),",
    "\n      refunded_by = COALESCE(refunded_by, $4::uuid),",
    sql,
)

sql = re.sub(
    r"\n\s*refund_payment_id\s*=\s*COALESCE\([^\n]*\),",
    "\n      refund_payment_id = COALESCE(refund_payment_id, $5::uuid),",
    sql,
)

block2 = block[:m.start(1)] + sql + block[m.end(1):]
s2 = s[:fn_pos] + block2

svc_path.write_text(s2, encoding="utf-8")
print("✅ service patched")
PY

echo "==> Patch routes: purchases.routes.ts (ensure correct body -> service args mapping)"
python3 - "$ROUTES" <<'PY'
import sys, re
from pathlib import Path

routes_path = Path(sys.argv[1])
t = routes_path.read_text(encoding="utf-8")

# Find refund route by path string
idx = t.find('"/purchases/:purchaseId/refund"')
if idx == -1:
    idx = t.find("'/purchases/:purchaseId/refund'")
if idx == -1:
    raise SystemExit("❌ Could not find /purchases/:purchaseId/refund route")

call_idx = t.find("refundPropertyPurchase(", idx)
if call_idx == -1:
    raise SystemExit("❌ Could not find refundPropertyPurchase(...) call in refund route")

line_start = t.rfind("\n", 0, call_idx) + 1

snippet = """
    // --- audit-safe mapping (accepts camelCase or snake_case) ---
    const body: any = (request as any).body ?? {};
    const refundMethod = body.refundMethod ?? body.refund_method ?? null;
    const reason = body.reason ?? body.refundReason ?? body.refunded_reason ?? null;
    const refundPaymentId = body.refundPaymentId ?? body.refund_payment_id ?? null;

    // best-effort refunded_by from auth user
    const refundedBy =
      ((request as any).user?.id ?? (request as any).userId ?? (request as any).auth?.user?.id ?? null);
"""

# Insert snippet once
pre = t[line_start:call_idx]
if "audit-safe mapping" not in pre:
    t = t[:line_start] + snippet + t[line_start:]

# Patch the call object inside ~6k chars after route start
region = t[idx: idx + 6000]
m = re.search(r"refundPropertyPurchase\(\s*client\s*,\s*\{([\s\S]*?)\}\s*\)", region)
if not m:
    raise SystemExit("❌ Could not parse refundPropertyPurchase(client, { ... })")

obj = "{"+m.group(1)+"}"

def ensure(obj_text: str, key: str, val: str) -> str:
    if re.search(rf"\b{re.escape(key)}\s*:", obj_text):
        obj_text = re.sub(rf"\b{re.escape(key)}\s*:\s*[^,\n]+", f"{key}: {val}", obj_text)
    else:
        obj_text = obj_text.rstrip().rstrip("}") + f",\n      {key}: {val},\n    }}"
    return obj_text

obj = ensure(obj, "refundMethod", "refundMethod")
obj = ensure(obj, "reason", "reason")
obj = ensure(obj, "refundPaymentId", "refundPaymentId")
obj = ensure(obj, "refundedBy", "refundedBy")

region2 = region[:m.start()] + "refundPropertyPurchase(client, " + obj + ")" + region[m.end():]
t2 = t[:idx] + region2 + t[idx+6000:]

routes_path.write_text(t2, encoding="utf-8")
print("✅ routes patched")
PY

echo "==> Typecheck"
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

cat <<'NEXT'

✅ DONE.

NEXT:
1) restart dev server:
   npm run dev

2) re-login / refresh env:
   export API="http://127.0.0.1:4000"
   eval "$(./scripts/login.sh)"
   export ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"

3) set purchase:
   export PURCHASE_ID="f72177d5-38ea-499f-86c7-8f4f1e063a02"

4) re-call refund (idempotent) with audit fields:
   curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
     -H "content-type: application/json" \
     -H "authorization: Bearer $TOKEN" \
     -H "x-organization-id: $ORG_ID" \
     -d '{"refundMethod":"card","amount":2000,"reason":"buyer cancelled","refundPaymentId":"21c4d5c8-94b5-4330-b34e-96173d2e4684"}' | jq

5) verify DB:
   PAGER=cat psql -d "$DB_NAME" -X -c "select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;"

NEXT
