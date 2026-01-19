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
import re
from pathlib import Path

path = Path("src/services/purchase_payments.service.ts")
s = path.read_text(encoding="utf-8")

# ------------------------------------------------------------
# 1) Ensure PURCHASE_SELECT includes milestone fields
# ------------------------------------------------------------
if "payment_status::text AS payment_status" not in s:
    # Insert right after deleted_at::text AS deleted_at inside PURCHASE_SELECT template string
    pat = r"(const\s+PURCHASE_SELECT\s*=\s*`[\s\S]*?deleted_at::text\s+AS\s+deleted_at)"
    m = re.search(pat, s)
    if not m:
        raise SystemExit("❌ Could not find PURCHASE_SELECT block to extend.")
    insert = (
        ",\n  payment_status::text AS payment_status,\n"
        "  paid_at::text AS paid_at,\n"
        "  paid_amount::text AS paid_amount,\n"
        "  last_payment_id::text AS last_payment_id"
    )
    s = s[:m.end()] + insert + s[m.end():]

# ------------------------------------------------------------
# 2) Replace the alreadyPaid block with idempotent milestone updater
#    Target: if (hasPayee && hasFee) { ... }
# ------------------------------------------------------------
replacement_block = r"""
  if (hasPayee && hasFee) {
    // Idempotent: ledger already credited.
    // Still ensure milestone fields are set (payment_status/paid_at/paid_amount/last_payment_id).

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

    const updated = await getPropertyPurchase(client, {
      organizationId: args.organizationId,
      purchaseId: purchase.id,
    });

    return { purchase: updated, alreadyPaid: true, platformFee: 0, sellerNet: 0 };
  }
"""

pat_paid = r"if\s*$begin:math:text$\\s\*hasPayee\\s\*\&\&\\s\*hasFee\\s\*$end:math:text$\s*\{[\s\S]*?\n\s*\}"
s2, n = re.subn(pat_paid, replacement_block.strip("\n"), s, count=1)
if n != 1:
    raise SystemExit("❌ Could not replace 'if (hasPayee && hasFee) { ... }' block (pattern not found).")
s = s2

# ------------------------------------------------------------
# 3) Ensure normal path sets milestone fields after ledger credits
#    Inject after first `await creditPayee(...);` if not present
# ------------------------------------------------------------
if "payment_status = 'paid'::purchase_payment_status" not in s:
    inject = r"""
  // Milestones: mark purchase as paid (without changing purchase_status lifecycle)
  const lastPay2 = await client.query<{ payment_id: string | null }>(
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

  const lastPaymentId2 = lastPay2.rows?.[0]?.payment_id ?? null;

  await client.query(
    `
    UPDATE public.property_purchases
    SET
      payment_status = 'paid'::purchase_payment_status,
      paid_at = COALESCE(paid_at, NOW()),
      paid_amount = COALESCE(paid_amount, 0) + $1::numeric,
      last_payment_id = COALESCE(last_payment_id, $2::uuid),
      updated_at = NOW()
    WHERE id = $3::uuid
      AND organization_id = $4::uuid
      AND deleted_at IS NULL;
    `,
    [amount, lastPaymentId2, purchase.id, args.organizationId]
  );
"""
    # place right after creditPayee(...) call (first occurrence)
    pat = r"(await\s+creditPayee$begin:math:text$\[\\s\\S\]\*\?$end:math:text$;\s*)"
    s3, n3 = re.subn(pat, r"\1" + inject, s, count=1)
    if n3 != 1:
        raise SystemExit("❌ Could not find creditPayee(...) call to inject milestone update.")
    s = s3

# ------------------------------------------------------------
# 4) Safety checks
# ------------------------------------------------------------
if "Idempotent: ledger already credited." not in s:
    raise SystemExit("❌ Patch incomplete: missing idempotent milestone comment after patch.")
if "payment_status::text AS payment_status" not in s:
    raise SystemExit("❌ Patch incomplete: PURCHASE_SELECT missing payment_status even after patch.")

path.write_text(s, encoding="utf-8")
print("✅ Python patch applied successfully.")
PY

echo "✅ PATCHED: $FILE"
echo ""
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Call pay endpoint again (idempotent is fine)"
echo "  3) Verify milestones:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select id, status, payment_status, paid_at, paid_amount, last_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
