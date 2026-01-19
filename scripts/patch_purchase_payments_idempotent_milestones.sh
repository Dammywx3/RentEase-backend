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

# 1) Extend PropertyPurchaseRow type with milestone fields (if missing)
perl -0777 -i -pe 's/export type PropertyPurchaseRow = \{\n([\s\S]*?)\n\};/export type PropertyPurchaseRow = {\n$1\n  payment_status?: string;\n  paid_at?: string | null;\n  paid_amount?: string | null;\n  last_payment_id?: string | null;\n};/m if $ARGV[0]' "$FILE"

# 2) Extend PURCHASE_SELECT to include milestone fields (if missing)
if ! grep -q "payment_status::text" "$FILE"; then
  perl -0777 -i -pe 's/const PURCHASE_SELECT = `\n([\s\S]*?)deleted_at::text AS deleted_at\n`;/const PURCHASE_SELECT = `\n$1deleted_at::text AS deleted_at,\n  payment_status::text AS payment_status,\n  paid_at::text AS paid_at,\n  paid_amount::text AS paid_amount,\n  last_payment_id::text AS last_payment_id\n`;/m' "$FILE"
fi

# 3) Fix alreadyPaid block:
#    - ensure milestone fields are set even if idempotent
#    - return platformFee/sellerNet as 0 when alreadyPaid
perl -0777 -i -pe 's/if \(hasPayee && hasFee\) \{\n\s*return \{ purchase, alreadyPaid: true, platformFee: 0, sellerNet: 0 \};\n\s*\}/if (hasPayee && hasFee) {\n    \/\/ Idempotent: ledger already credited.\n    \/\/ Still ensure purchase milestone fields are set (payment_status\/paid_at\/paid_amount\/last_payment_id).\n\n    const lastPay = await client.query<{ payment_id: string | null }>(\n      `\n      SELECT ppp.payment_id::text AS payment_id\n      FROM public.property_purchase_payments ppp\n      WHERE ppp.organization_id = $1::uuid\n        AND ppp.purchase_id = $2::uuid\n      ORDER BY ppp.created_at DESC\n      LIMIT 1;\n      `,\n      [args.organizationId, purchase.id]\n    );\n\n    const lastPaymentId = lastPay.rows?.[0]?.payment_id ?? null;\n\n    await client.query(\n      `\n      UPDATE public.property_purchases\n      SET\n        payment_status = 'paid'::purchase_payment_status,\n        paid_at = COALESCE(paid_at, NOW()),\n        paid_amount = COALESCE(paid_amount, agreed_price),\n        last_payment_id = COALESCE(last_payment_id, $1::uuid),\n        updated_at = NOW()\n      WHERE id = $2::uuid\n        AND organization_id = $3::uuid\n        AND deleted_at IS NULL;\n      `,\n      [lastPaymentId, purchase.id, args.organizationId]\n    );\n\n    const updated = await getPropertyPurchase(client, {\n      organizationId: args.organizationId,\n      purchaseId: purchase.id,\n    });\n\n    return { purchase: updated, alreadyPaid: true, platformFee: 0, sellerNet: 0 };\n  }/m' "$FILE"

# Sanity checks
if grep -q 'platformFee": 50' "$FILE"; then
  echo "⚠️ Note: found hardcoded 50 in file (unexpected). Please inspect."
fi

if ! grep -q "payment_status::text AS payment_status" "$FILE"; then
  echo "❌ Patch incomplete: PURCHASE_SELECT missing payment_status."
  exit 1
fi

if ! grep -q "Idempotent: ledger already credited" "$FILE"; then
  echo "❌ Patch incomplete: alreadyPaid milestone updater not inserted."
  exit 1
fi

echo "✅ PATCHED: $FILE"
echo "➡️ Next: restart server: npm run dev"
