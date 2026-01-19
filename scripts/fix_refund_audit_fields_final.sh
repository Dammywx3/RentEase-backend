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

echo "==> Patch service: purchase_refunds.service.ts (fix audit mapping + allow correction on idempotent)"
python3 - <<'PY'
from pathlib import Path
import re

svc_path = Path(r"""'"$SVC"'""")
s = svc_path.read_text(encoding="utf-8")

# Find the UPDATE block inside upsertRefundMilestones and replace only the audit-field SET lines.
# We'll anchor on "UPDATE public.property_purchases" and "WHERE id = $6::uuid" to avoid brittle regex.
upd_start = s.find("UPDATE public.property_purchases")
if upd_start == -1:
    raise SystemExit("❌ Could not find UPDATE public.property_purchases in upsertRefundMilestones")

# Narrow to the first occurrence after upsertRefundMilestones
fn_pos = s.find("async function upsertRefundMilestones")
if fn_pos == -1:
    raise SystemExit("❌ Could not find upsertRefundMilestones()")

block = s[fn_pos:]
upd_pos = block.find("UPDATE public.property_purchases")
if upd_pos == -1:
    raise SystemExit("❌ Could not find UPDATE inside upsertRefundMilestones()")

# Extract the SQL template content between backticks in that query call
m = re.search(r"await client\.query\(\s*`([\s\S]*?)`\s*,\s*\[", block)
if not m:
    raise SystemExit("❌ Could not locate SQL template backticks inside upsertRefundMilestones()")

sql = m.group(1)

# Ensure we have the columns we expect in SQL
needed = ["refund_method", "refunded_reason", "refunded_by", "refund_payment_id"]
if not all(k in sql for k in needed):
    raise SystemExit("❌ upsertRefundMilestones SQL does not include expected audit columns yet")

# Replace the audit SET lines with corrected logic
def replace_set(sql_text: str) -> str:
    # Replace any existing lines for these columns (keep indentation tolerant)
    sql_text = re.sub(r"\n\s*refund_method\s*=\s*COALESCE\([^\n]*\),",
                      "\n      refund_method = COALESCE(refund_method, $2::text),", sql_text)

    # refunded_reason: allow correcting previously-bad value like 'card'
    sql_text = re.sub(
        r"\n\s*refunded_reason\s*=\s*COALESCE\([^\n]*\),",
        "\n      refunded_reason = CASE\n"
        "        WHEN refunded_reason IS NULL THEN $3::text\n"
        "        WHEN refunded_reason IN ('card','bank_transfer','wallet')\n"
        "             AND $3::text IS NOT NULL\n"
        "             AND $3::text NOT IN ('card','bank_transfer','wallet') THEN $3::text\n"
        "        ELSE refunded_reason\n"
        "      END,",
        sql_text
    )

    sql_text = re.sub(r"\n\s*refunded_by\s*=\s*COALESCE\([^\n]*\),",
                      "\n      refunded_by = COALESCE(refunded_by, $4::uuid),", sql_text)

    sql_text = re.sub(r"\n\s*refund_payment_id\s*=\s*COALESCE\([^\n]*\),",
                      "\n      refund_payment_id = COALESCE(refund_payment_id, $5::uuid),", sql_text)

    return sql_text

sql2 = replace_set(sql)

# Put the SQL back
block2 = block[:m.start(1)] + sql2 + block[m.end(1):]
s2 = s[:fn_pos] + block2

svc_path.write_text(s2, encoding="utf-8")
print("✅ service patched")
PY

echo "==> Patch routes: purchases.routes.ts (ensure correct body mapping to service args)"
python3 - <<'PY'
from pathlib import Path
import re

routes_path = Path(r"""'"$ROUTES"'""")
t = routes_path.read_text(encoding="utf-8")

# Find the refund route handler block by its path
idx = t.find('"/purchases/:purchaseId/refund"')
if idx == -1:
    idx = t.find("'/purchases/:purchaseId/refund'")
if idx == -1:
    raise SystemExit("❌ Could not find /purchases/:purchaseId/refund route")

# We'll insert a safe mapping snippet near the call to refundPropertyPurchase(...).
# Find the first occurrence of "refundPropertyPurchase(" after the route index.
call_idx = t.find("refundPropertyPurchase(", idx)
if call_idx == -1:
    raise SystemExit("❌ Could not find refundPropertyPurchase(...) call in refund route")

# Find a good insertion point just before the call (start of the line containing it)
line_start = t.rfind("\n", 0, call_idx) + 1

snippet = """
    // --- audit-safe mapping (accepts camelCase or snake_case) ---
    const body: any = (request as any).body ?? {};
    const refundMethod = body.refundMethod ?? body.refund_method ?? null;
    const reason = body.reason ?? body.refundReason ?? body.refunded_reason ?? null;
    const refundPaymentId = body.refundPaymentId ?? body.refund_payment_id ?? null;

    // best-effort "refunded_by" from auth user (depends on your auth plugin)
    const refundedBy =
      ((request as any).user?.id ?? (request as any).userId ?? (request as any).auth?.user?.id ?? null);
"""

# Avoid double-inserting
if "audit-safe mapping" not in t[line_start:call_idx]:
    t = t[:line_start] + snippet + t[line_start:]

# Now patch the actual call object to pass the right fields.
# We replace the first object literal argument that includes organizationId/purchaseId in this call scope.
# This is conservative: only patches inside this refund route region.
region = t[idx: idx + 6000]

# Replace common wrong mappings if present, otherwise ensure fields exist
def ensure_fields(obj: str) -> str:
    # Ensure refundMethod, reason, refundPaymentId, refundedBy are passed
    if "refundMethod:" not in obj:
        obj = obj.rstrip().rstrip("}") + ",\n      refundMethod,\n    }"
    else:
        obj = re.sub(r"refundMethod\s*:\s*[^,\n]+", "refundMethod", obj)

    if "reason:" not in obj:
        obj = obj.rstrip().rstrip("}") + ",\n      reason,\n    }"
    else:
        obj = re.sub(r"reason\s*:\s*[^,\n]+", "reason", obj)

    if "refundPaymentId:" not in obj:
        obj = obj.rstrip().rstrip("}") + ",\n      refundPaymentId,\n    }"
    else:
        obj = re.sub(r"refundPaymentId\s*:\s*[^,\n]+", "refundPaymentId", obj)

    if "refundedBy:" not in obj:
        obj = obj.rstrip().rstrip("}") + ",\n      refundedBy,\n    }"
    else:
        obj = re.sub(r"refundedBy\s*:\s*[^,\n]+", "refundedBy", obj)

    return obj

# Patch the call args object inside the refund route region
m = re.search(r"refundPropertyPurchase\(\s*client\s*,\s*\{([\s\S]*?)\}\s*\)", region)
if not m:
    raise SystemExit("❌ Could not parse refundPropertyPurchase(client, { ... }) in refund route")

obj_text = "{"+m.group(1)+"}"
obj_fixed = ensure_fields(obj_text)

region2 = region[:m.start()] + "refundPropertyPurchase(client, " + obj_fixed + ")" + region[m.end():]
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

2) re-login / refresh env vars (important):
   export API="http://127.0.0.1:4000"
   eval "$(./scripts/login.sh)"
   export ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"

3) set PURCHASE_ID (yours is fine):
   export PURCHASE_ID="f72177d5-38ea-499f-86c7-8f4f1e063a02"

4) re-call refund (idempotent) with audit fields:
   curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
     -H "content-type: application/json" \
     -H "authorization: Bearer $TOKEN" \
     -H "x-organization-id: $ORG_ID" \
     -d '{"refundMethod":"card","amount":2000,"reason":"buyer cancelled","refundPaymentId":"21c4d5c8-94b5-4330-b34e-96173d2e4684"}' | jq

5) verify DB (now should NOT be null, and refunded_reason should be buyer cancelled):
   PAGER=cat psql -d "$DB_NAME" -X -c "select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;"

NEXT
