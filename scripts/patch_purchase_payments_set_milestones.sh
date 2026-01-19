#!/usr/bin/env bash
set -eo pipefail

FILE="src/services/purchase_payments.service.ts"

[ -f "$FILE" ] || { echo "❌ Missing: $FILE"; exit 1; }

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "scripts/.bak/purchase_payments.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.$ts"

python3 - <<'PY'
from pathlib import Path

p = Path("src/services/purchase_payments.service.ts")
s = p.read_text()

# If milestone update already exists, skip
if "purchase_payment_status" in s and "paid_amount" in s and "last_payment_id" in s and "property_purchase_payments" in s:
    print("✅ Milestone update appears present already (skipping)")
    raise SystemExit(0)

needle = "await creditPayee(client, {"
i = s.find(needle)
if i == -1:
    raise SystemExit("❌ Could not find creditPayee(...) call to anchor patch")

# find end of the creditPayee call (first occurrence of '});' after it)
end = s.find("});", i)
if end == -1:
    raise SystemExit("❌ Could not find end of creditPayee(...) call")
end = end + len("});")

insert_block = """

  // 3) Update purchase payment milestone fields (does NOT change lifecycle status enum)
  // payment_status tracks money state; status tracks workflow (under_contract, escrow_opened, closing_scheduled, etc.)
  await client.query(
    `
    UPDATE public.property_purchases pp
    SET
      paid_at = COALESCE(pp.paid_at, NOW()),
      paid_amount = COALESCE(pp.paid_amount, 0) + $1::numeric,
      payment_status = CASE
        WHEN (COALESCE(pp.paid_amount, 0) + $1::numeric) >= pp.agreed_price THEN 'paid'::purchase_payment_status
        WHEN (COALESCE(pp.paid_amount, 0) + $1::numeric) > 0 THEN 'partially_paid'::purchase_payment_status
        ELSE pp.payment_status
      END,
      last_payment_id = COALESCE(
        (
          SELECT ppp.payment_id
          FROM public.property_purchase_payments ppp
          WHERE ppp.purchase_id = pp.id
          ORDER BY ppp.created_at DESC
          LIMIT 1
        ),
        pp.last_payment_id
      ),
      updated_at = NOW()
    WHERE pp.id = $2::uuid
      AND pp.organization_id = $3::uuid
      AND pp.deleted_at IS NULL;
    `,
    [amount, purchase.id, args.organizationId]
  );

"""

# insert right after creditPayee(...) call
s2 = s[:end] + insert_block + s[end:]

p.write_text(s2)
print("✅ PATCHED:", str(p))
PY

echo ""
echo "✅ DONE"
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Call pay endpoint again (idempotent is fine)"
echo "  3) Verify milestones:"
echo "     PAGER=cat psql -d \"$DB_NAME\" -X -c \"select id, status, payment_status, paid_at, paid_amount, last_payment_id from public.property_purchases where id='$PURCHASE_ID'::uuid;\""
