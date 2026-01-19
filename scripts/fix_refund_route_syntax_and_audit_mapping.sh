#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.before_fix.$TS"
echo "✅ backup current (broken) -> scripts/.bak/purchases.routes.ts.bak.before_fix.$TS"

# Restore latest known-good backup created by your previous script(s)
LATEST_BAK="$(ls -t "$ROOT/scripts/.bak/purchases.routes.ts.bak."* 2>/dev/null | head -n 1 || true)"
if [ -z "${LATEST_BAK:-}" ]; then
  echo "❌ No backups found in scripts/.bak for purchases.routes.ts"
  echo "   Expected something like: scripts/.bak/purchases.routes.ts.bak.YYYYMMDD_HHMMSS"
  exit 1
fi

cp "$LATEST_BAK" "$ROUTES"
echo "✅ restored routes from: $LATEST_BAK"

echo "==> Patch refund route safely (no broken commas)"
python3 - "$ROUTES" <<'PY'
import sys, re
from pathlib import Path

p = Path(sys.argv[1])
t = p.read_text(encoding="utf-8")

# Locate the refund route block
route_pos = t.find('"/purchases/:purchaseId/refund"')
if route_pos == -1:
    route_pos = t.find("'/purchases/:purchaseId/refund'")
if route_pos == -1:
    raise SystemExit("❌ Could not find /purchases/:purchaseId/refund route")

call_pos = t.find("refundPropertyPurchase(", route_pos)
if call_pos == -1:
    raise SystemExit("❌ Could not find refundPropertyPurchase(...) call near refund route")

# Insert audit mapping snippet right before the call (idempotent)
line_start = t.rfind("\n", 0, call_pos) + 1
before_call = t[line_start:call_pos]
marker = "refund audit mapping (safe)"
if marker not in t[route_pos:call_pos]:
    snippet = (
        "    // --- refund audit mapping (safe) ---\n"
        "    const body: any = (request as any).body ?? {};\n"
        "    const refundMethod = body.refundMethod ?? body.refund_method ?? null;\n"
        "    const reason = body.reason ?? body.refundReason ?? body.refunded_reason ?? null;\n"
        "    const refundPaymentId = body.refundPaymentId ?? body.refund_payment_id ?? null;\n"
        "    const refundedBy = ((request as any).user?.id ?? (request as any).userId ?? (request as any).auth?.user?.id ?? null);\n"
        "\n"
    )
    t = t[:line_start] + snippet + t[line_start:]
    # call_pos shifts; recompute
    call_pos = t.find("refundPropertyPurchase(", route_pos)

# Find the object literal passed into refundPropertyPurchase(client, { ... })
obj_start = t.find("{", call_pos)
if obj_start == -1:
    raise SystemExit("❌ Could not find '{' after refundPropertyPurchase(")

# Brace-balanced scan to find matching closing brace of that object
i = obj_start
depth = 0
in_str = None
esc = False
obj_end = None
for j in range(obj_start, len(t)):
    ch = t[j]
    if in_str:
        if esc:
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == in_str:
            in_str = None
        continue
    else:
        if ch in ("'", '"', "`"):
            in_str = ch
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                obj_end = j
                break

if obj_end is None:
    raise SystemExit("❌ Could not find end of object literal for refundPropertyPurchase")

obj_body = t[obj_start+1:obj_end]

# Remove any existing audit keys (camelCase or snake_case), to avoid duplicates
obj_body2 = re.sub(
    r"(?m)^\s*(refundMethod|reason|refundPaymentId|refundedBy|refund_method|refunded_reason|refund_payment_id|refunded_by)\s*:\s*.*?,?\s*$",
    "",
    obj_body
)

# Normalize: keep only non-empty lines
lines = [ln.rstrip() for ln in obj_body2.splitlines() if ln.strip()]

# Ensure the last existing property line ends with a comma (so we can append safely)
if lines:
    if not lines[-1].rstrip().endswith(","):
        lines[-1] = lines[-1].rstrip() + ","

# Append correct audit mappings (what you WANT):
# refund_method -> "card"
# refunded_reason -> "buyer cancelled"
# refund_payment_id -> uuid
# refunded_by -> current user id
append = [
    "      refundMethod: refundMethod,",
    "      reason: reason,",
    "      refundPaymentId: refundPaymentId,",
    "      refundedBy: refundedBy,",
]

# If the object is empty (unlikely), still insert cleanly
if not lines:
    # try to infer indentation from nearby text; default to 6 spaces
    pass

lines.extend(append)
new_obj_body = "\n".join(lines) + "\n"

# Replace in the full file
t2 = t[:obj_start+1] + new_obj_body + t[obj_end:]

p.write_text(t2, encoding="utf-8")
print("✅ refund route object patched safely")
PY

echo "==> Typecheck"
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

cat <<'NEXT'

✅ DONE.

NEXT:
1) restart dev server:
   npm run dev

2) refresh env:
   export API="http://127.0.0.1:4000"
   eval "$(./scripts/login.sh)"
   export ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
   export PURCHASE_ID="f72177d5-38ea-499f-86c7-8f4f1e063a02"

3) call refund again (idempotent) WITH audit fields:
   curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
     -H "content-type: application/json" \
     -H "authorization: Bearer $TOKEN" \
     -H "x-organization-id: $ORG_ID" \
     -d '{"refundMethod":"card","amount":2000,"reason":"buyer cancelled","refundPaymentId":"21c4d5c8-94b5-4330-b34e-96173d2e4684"}' | jq

4) verify DB:
   PAGER=cat psql -d "$DB_NAME" -X -c "select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;"

EXPECTED:
- refund_method = card
- refunded_reason = buyer cancelled
- refund_payment_id = 21c4... uuid
- refunded_by = your user id

NEXT
