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

# -------------------------------------------------------------------
# 1) Ensure PURCHASE_SELECT includes milestone columns (if missing)
# -------------------------------------------------------------------
if ! grep -q "payment_status::text AS payment_status" "$FILE"; then
  perl -0777 -i -pe '
    s/(const\s+PURCHASE_SELECT\s*=\s*`\s*\n[\s\S]*?deleted_at::text\s+AS\s+deleted_at)(\s*\n`;)/
$1,
  payment_status::text AS payment_status,
  paid_at::text AS paid_at,
  paid_amount::text AS paid_amount,
  last_payment_id::text AS last_payment_id
$2/m
  ' "$FILE"
fi

# -------------------------------------------------------------------
# 2) Replace ANY "if (hasPayee && hasFee) { ... }" block with idempotent milestone updater
# -------------------------------------------------------------------
perl -0777 -i -pe '
  my $replacement = q{
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
        payment_status = \'paid\'::purchase_payment_status,
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
};

  # Replace the first occurrence only (there should be only one)
  s/if\s*\(\s*hasPayee\s*&&\s*hasFee\s*\)\s*\{[\s\S]*?\n\s*\}/$replacement/m;
' "$FILE"

# -------------------------------------------------------------------
# 3) Ensure normal (non-idempotent) path sets milestones after ledger credits
#    We inject right AFTER the creditPayee(...) call, if not already present.
# -------------------------------------------------------------------
if ! grep -q "payment_status = 'paid'::purchase_payment_status" "$FILE"; then
  perl -0777 -i -pe '
    s/(await\s+creditPayee\([\s\S]*?\);\s*)/$1\n  \/\/ Milestones: mark purchase as paid (without changing purchase_status lifecycle)\n  const lastPay2 = await client.query<{ payment_id: string | null }>(\n    `\n    SELECT ppp.payment_id::text AS payment_id\n    FROM public.property_purchase_payments ppp\n    WHERE ppp.organization_id = $1::uuid\n      AND ppp.purchase_id = $2::uuid\n    ORDER BY ppp.created_at DESC\n    LIMIT 1;\n    `,\n    [args.organizationId, purchase.id]\n  );\n\n  const lastPaymentId2 = lastPay2.rows?.[0]?.payment_id ?? null;\n\n  await client.query(\n    `\n    UPDATE public.property_purchases\n    SET\n      payment_status = \'paid\'::purchase_payment_status,\n      paid_at = COALESCE(paid_at, NOW()),\n      paid_amount = COALESCE(paid_amount, 0) + $1::numeric,\n      last_payment_id = COALESCE(last_payment_id, $2::uuid),\n      updated_at = NOW()\n    WHERE id = $3::uuid\n      AND organization_id = $4::uuid\n      AND deleted_at IS NULL;\n    `,\n    [amount, lastPaymentId2, purchase.id, args.organizationId]\n  );\n/sm
  ' "$FILE"
fi

# -------------------------------------------------------------------
# 4) Hard checks
# -------------------------------------------------------------------
if ! grep -q "Idempotent: ledger already credited" "$FILE"; then
  echo "❌ Patch failed: could not replace alreadyPaid block."
  exit 1
fi

if ! grep -q "payment_status::text AS payment_status" "$FILE"; then
  echo "❌ Patch failed: PURCHASE_SELECT still missing payment_status."
  exit 1
fi

echo "✅ PATCHED: $FILE"
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Call pay endpoint again (idempotent is fine)"
echo "  3) Verify milestones:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select id, status, payment_status, paid_at, paid_amount, last_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
