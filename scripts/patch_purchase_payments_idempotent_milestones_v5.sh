#!/usr/bin/env bash
set -euo pipefail

FILE="src/services/purchase_payments.service.ts"
if [[ ! -f "$FILE" ]]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p scripts/.bak
cp "$FILE" "scripts/.bak/purchase_payments.service.ts.bak.$TS"
echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.$TS"

python3 - <<'PY'
from pathlib import Path
import re

path = Path("src/services/purchase_payments.service.ts")
s = path.read_text(encoding="utf-8")

# -----------------------------
# 0) Helpers
# -----------------------------
def ensure_once(haystack: str, needle: str) -> bool:
    return needle in haystack

milestone_block = r"""
  // ------------------------------------------------------------
  // Milestones: mark purchase as paid (without changing lifecycle enum)
  // - payment_status='paid'
  // - paid_at set once
  // - paid_amount defaults to agreed_price
  // - last_payment_id set from latest purchase-payment link (if exists)
  // ------------------------------------------------------------
  const lastPay = await client.query<{ payment_id: string | null }>(
    `
    SELECT ppp.payment_id::text AS payment_id
    FROM public.property_purchase_payments ppp
    WHERE ppp.organization_id = $1::uuid
      AND ppp.purchase_id = $2::uuid
    ORDER BY ppp.created_at DESC
    LIMIT 1;
    `,
    [args.organizationId, purchase.id]
  );

  const lastPaymentId = lastPay.rows?.[0]?.payment_id ?? null;

  await client.query(
    `
    UPDATE public.property_purchases
    SET
      payment_status = 'paid'::purchase_payment_status,
      paid_at = COALESCE(paid_at, NOW()),
      paid_amount = COALESCE(paid_amount, agreed_price),
      last_payment_id = COALESCE(last_payment_id, $1::uuid),
      updated_at = NOW()
    WHERE id = $2::uuid
      AND organization_id = $3::uuid
      AND deleted_at IS NULL;
    `,
    [lastPaymentId, purchase.id, args.organizationId]
  );
"""

# -----------------------------
# 1) Ensure PURCHASE_SELECT includes milestone fields
# -----------------------------
if "const PURCHASE_SELECT" not in s:
    raise SystemExit("❌ Could not find PURCHASE_SELECT constant.")

if "payment_status::text AS payment_status" not in s:
    # Add milestone fields after deleted_at select line
    pat = r"(const\s+PURCHASE_SELECT\s*=\s*`[\s\S]*?deleted_at::text\s+AS\s+deleted_at)"
    m = re.search(pat, s)
    if not m:
        raise SystemExit("❌ Could not locate deleted_at field inside PURCHASE_SELECT.")

    extra = (
        ",\n  payment_status::text AS payment_status,\n"
        "  paid_at::text AS paid_at,\n"
        "  paid_amount::text AS paid_amount,\n"
        "  last_payment_id::text AS last_payment_id"
    )
    s = s[:m.end()] + extra + s[m.end():]

# -----------------------------
# 2) Patch idempotent return (alreadyPaid:true) to set milestones before returning
# Anchor exactly the return line you have.
# -----------------------------
idempotent_return_pat = re.compile(
    r"\n(\s*)return\s*\{\s*purchase\s*,\s*alreadyPaid\s*:\s*true\s*,\s*platformFee\s*:\s*split\.platformFee\s*,\s*sellerNet\s*:\s*split\.payeeNet\s*\}\s*;\s*",
    re.MULTILINE
)

if idempotent_return_pat.search(s):
    # Avoid double insert
    if "Milestones: mark purchase as paid" not in s:
        def repl(m):
            indent = m.group(1)
            block = "\n".join(indent + line if line.strip() else line for line in milestone_block.splitlines())
            return "\n" + block + "\n" + indent + "return { purchase, alreadyPaid: true, platformFee: split.platformFee, sellerNet: split.payeeNet };\n"
        s, n = idempotent_return_pat.subn(repl, s, count=1)
        if n != 1:
            raise SystemExit("❌ Failed to inject milestone block before idempotent return.")
else:
    raise SystemExit("❌ Could not find the idempotent alreadyPaid:true return to patch. (Search for 'alreadyPaid: true' and rerun)")

# -----------------------------
# 3) Ensure normal path sets milestones after ledger credits.
# Insert right AFTER the first creditPayee(...) await call if not already present.
# -----------------------------
if "payment_status = 'paid'::purchase_payment_status" not in s:
    payee_pat = re.compile(r"(await\s+creditPayee$begin:math:text$\[\\s\\S\]\*\?$end:math:text$;\s*)", re.MULTILINE)
    m = payee_pat.search(s)
    if not m:
        raise SystemExit("❌ Could not find await creditPayee(...) call to inject milestones after ledger credits.")
    insert_at = m.end(1)
    s = s[:insert_at] + "\n" + milestone_block + "\n" + s[insert_at:]

# -----------------------------
# 4) Safety checks
# -----------------------------
if "payment_status::text AS payment_status" not in s:
    raise SystemExit("❌ Patch incomplete: PURCHASE_SELECT missing payment_status.")
if "Milestones: mark purchase as paid" not in s:
    raise SystemExit("❌ Patch incomplete: milestone block missing.")
if "last_payment_id" not in s:
    raise SystemExit("❌ Patch incomplete: last_payment_id not present (unexpected).")

path.write_text(s, encoding="utf-8")
print("✅ v5 patch applied.")
PY

echo "✅ PATCHED: $FILE"
echo ""
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Call pay endpoint again (idempotent is fine)"
echo "  3) Verify milestones:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select id, status, payment_status, paid_at, paid_amount, last_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
