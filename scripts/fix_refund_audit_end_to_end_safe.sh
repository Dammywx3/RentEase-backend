#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC="$ROOT/src/services/purchase_refunds.service.ts"
ROUTES="$ROOT/src/routes/purchases.routes.ts"

[ -f "$SVC" ] || { echo "❌ Not found: $SVC"; exit 1; }
[ -f "$ROUTES" ] || { echo "❌ Not found: $ROUTES"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$ROOT/scripts/.bak"
cp "$SVC" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.before_fix.$TS"
cp "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.before_fix.$TS"
echo "✅ backups -> scripts/.bak/*before_fix.$TS"

echo "==> Step 1: restore service from latest backup that typechecks (if currently broken)"
restore_typecheck () {
  local target="$1"
  local pattern="$2"

  # First try current file
  if npx -y tsc -p "$ROOT/tsconfig.json" --noEmit >/dev/null 2>&1; then
    echo "✅ project already typechecks; no restore needed"
    return 0
  fi

  # Try backups newest -> oldest
  local found=""
  for b in $(ls -t $pattern 2>/dev/null || true); do
    cp "$b" "$target"
    if npx -y tsc -p "$ROOT/tsconfig.json" --noEmit >/dev/null 2>&1; then
      found="$b"
      break
    fi
  done

  if [ -z "$found" ]; then
    echo "❌ Could not find a backup that makes TypeScript pass."
    echo "   You can manually restore one from scripts/.bak and rerun."
    exit 1
  fi

  echo "✅ Restored $target from: $found"
}

restore_typecheck "$SVC" "$ROOT/scripts/.bak/purchase_refunds.service.ts.bak.*"
# routes may be broken too; try restoring if still failing
if ! npx -y tsc -p "$ROOT/tsconfig.json" --noEmit >/dev/null 2>&1; then
  restore_typecheck "$ROUTES" "$ROOT/scripts/.bak/purchases.routes.ts.bak.*"
fi

echo "==> Step 2: patch SERVICE mapping (safe, no shell expansion)"
SVC_PATH="$SVC" python3 - <<'PY'
import os, re
from pathlib import Path

svc = Path(os.environ["SVC_PATH"])
s = svc.read_text(encoding="utf-8")

# 0) helper functions (avoid "" for uuid/text)
if "function cleanUuid" not in s:
    s = re.sub(
        r'^(import[^\n]*\n(?:import[^\n]*\n)*)',
        r"""\1
function cleanUuid(v: any): string | null {
  if (v === null || v === undefined) return null;
  const t = String(v).trim();
  return t.length ? t : null;
}
function cleanText(v: any): string | null {
  if (v === null || v === undefined) return null;
  const t = String(v).trim();
  return t.length ? t : null;
}

""",
        s, count=1, flags=re.M
    )

# 1) Replace upsertRefundMilestones block by anchors
pat = re.compile(r"async function upsertRefundMilestones\s*\([\s\S]*?\n\}\n", re.M)
m = pat.search(s)
if not m:
    raise SystemExit("❌ Could not find upsertRefundMilestones() in service")

replacement = r"""async function upsertRefundMilestones(
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

      -- audit fields
      refund_method = COALESCE(refund_method, $2::text),

      -- IMPORTANT:
      -- If refunded_reason is NULL OR incorrectly equals refund_method (old bug),
      -- replace it with the provided reason.
      refunded_reason = CASE
        WHEN $3::text IS NULL THEN refunded_reason
        WHEN refunded_reason IS NULL THEN $3::text
        WHEN refund_method IS NOT NULL AND refunded_reason = refund_method THEN $3::text
        ELSE refunded_reason
      END,

      refunded_by = COALESCE(refunded_by, $4::uuid),
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

# 2) Ensure ALL calls include lastPaymentId (to avoid TS2345)
# We'll patch any "upsertRefundMilestones(client, { ... })" object that lacks lastPaymentId.
call_pat = re.compile(r"upsertRefundMilestones\(\s*client\s*,\s*\{([\s\S]*?)\}\s*\)", re.M)

def add_last_payment(body: str) -> str:
    if re.search(r"\blastPaymentId\s*:", body):
        return body
    # if purchase is in scope use purchase.last_payment_id
    if "purchase." in body:
        return re.sub(r"(amount\s*:\s*[^,\n]+,\s*)", r"\1\n      lastPaymentId: purchase.last_payment_id ?? null,\n", body, count=1)
    # otherwise leave (better to fail than guess)
    return body

def repl(mm):
    inner = mm.group(1)
    inner2 = add_last_payment(inner)
    return "upsertRefundMilestones(client, {\n" + inner2 + "\n    })"

s2 = call_pat.sub(repl, s)
s = s2

svc.write_text(s, encoding="utf-8")
print("✅ service patched:", svc)
PY

echo "==> Step 3: patch ROUTE to pass correct body fields (safe object append, no broken commas)"
ROUTES_PATH="$ROUTES" python3 - <<'PY'
import os, re
from pathlib import Path

routes = Path(os.environ["ROUTES_PATH"])
t = routes.read_text(encoding="utf-8")

# Find the refund handler by locating refundPropertyPurchase call
idx = t.find("refundPropertyPurchase")
if idx == -1:
    print("⚠️ Could not find refundPropertyPurchase in routes; skipping route patch.")
    routes.write_text(t, encoding="utf-8")
    raise SystemExit(0)

# Insert safe extraction lines once near the refundPropertyPurchase call site
# We'll add these right above the call if not present.
before = t[:idx]
after = t[idx:]

if "const refundMethod" not in after[:800] and "let refundMethod" not in after[:800]:
    # try to find a 'const body =' or direct 'req.body' usage
    insert_point = before.rfind("\n", 0, len(before))
    snippet_start = max(0, insert_point - 500)
    # Find the start of the statement line containing refundPropertyPurchase
    line_start = before.rfind("\n", 0, idx)
    if line_start == -1:
        line_start = 0
    # Insert before that line
    t = t[:line_start] + """
    const body: any = req.body ?? {};
    const refundMethod = body.refundMethod ?? null;
    const reason = body.reason ?? null;
    const refundPaymentId = body.refundPaymentId ?? null;
    const refundedBy = (req as any).user?.id ?? null;
""" + t[line_start:]

# Now ensure the argument object includes these keys (append if missing)
# We do a conservative patch: locate the first occurrence of refundPropertyPurchase( ... { ... } ... )
m = re.search(r"refundPropertyPurchase\s*\(\s*([^\),]+)\s*,\s*\{", t)
if not m:
    print("⚠️ Could not locate refundPropertyPurchase(client, { ... }) pattern; skipping object patch.")
    routes.write_text(t, encoding="utf-8")
    raise SystemExit(0)

start = m.end()  # position after the "{"
# find matching closing brace for that object
depth = 1
i = start
while i < len(t) and depth > 0:
    if t[i] == "{":
        depth += 1
    elif t[i] == "}":
        depth -= 1
    i += 1

obj_end = i - 1
obj = t[start:obj_end]

def ensure_line(obj: str, key: str, expr: str) -> str:
    if re.search(rf"\b{re.escape(key)}\s*:", obj):
        return obj
    # append with a trailing comma
    # try to keep indentation similar (2 spaces or 4 spaces)
    indent = "      " if "      " in obj else "    "
    return obj.rstrip() + f"\n{indent}{key}: {expr},\n"

obj2 = obj
obj2 = ensure_line(obj2, "refundMethod", "refundMethod")
obj2 = ensure_line(obj2, "reason", "reason")
obj2 = ensure_line(obj2, "refundPaymentId", "refundPaymentId")
obj2 = ensure_line(obj2, "refundedBy", "refundedBy")

t2 = t[:start] + obj2 + t[obj_end:]
routes.write_text(t2, encoding="utf-8")
print("✅ routes patched:", routes)
PY

echo "==> Step 4: typecheck"
npx -y tsc -p "$ROOT/tsconfig.json" --noEmit
echo "✅ OK"

cat <<'NEXT'

✅ DONE.

NEXT:
1) restart dev server:
   npm run dev

2) refresh vars:
   export API="http://127.0.0.1:4000"
   eval "$(./scripts/login.sh)"
   export ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"
   export USER_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.id')"
   export PURCHASE_ID="f72177d5-38ea-499f-86c7-8f4f1e063a02"

3) call refund again (idempotent) WITH refundedBy:
   curl -sS -X POST "$API/v1/purchases/$PURCHASE_ID/refund" \
     -H "content-type: application/json" \
     -H "authorization: Bearer $TOKEN" \
     -H "x-organization-id: $ORG_ID" \
     -d "{\"refundMethod\":\"card\",\"amount\":2000,\"reason\":\"buyer cancelled\",\"refundPaymentId\":\"21c4d5c8-94b5-4330-b34e-96173d2e4684\",\"refundedBy\":\"$USER_ID\"}" | jq

4) verify DB:
   PAGER=cat psql -d "$DB_NAME" -X -c "select refund_method, refunded_reason, refunded_by, refund_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;"

Expected:
- refund_method = card
- refunded_reason = buyer cancelled
- refunded_by = (your user id)
- refund_payment_id = 21c4d5c8-...

NEXT
