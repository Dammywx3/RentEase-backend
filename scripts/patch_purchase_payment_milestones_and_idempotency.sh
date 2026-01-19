#!/usr/bin/env bash
set -eo pipefail

ROOT="$(pwd)"
FILE="src/services/purchase_payments.service.ts"

echo "ROOT=$ROOT"

if [ ! -f "$FILE" ]; then
  echo "❌ Not found: $FILE"
  exit 1
fi

mkdir -p scripts/.bak
ts="$(date +%Y%m%d_%H%M%S)"
cp "$FILE" "scripts/.bak/purchase_payments.service.ts.bak.${ts}"
echo "✅ backup -> scripts/.bak/purchase_payments.service.ts.bak.${ts}"

# ------------------------------------------------------------
# Patch 1: fix "alreadyPaid" branch to return real split values
# ------------------------------------------------------------
perl -0777 -i -pe '
  s/if\s*\(hasPayee\s*&&\s*hasFee\)\s*\{\s*return\s*\{\s*purchase,\s*alreadyPaid:\s*true,\s*platformFee:\s*0,\s*sellerNet:\s*0\s*\};\s*\}/if (hasPayee \&\& hasFee) {\n    const agreed = Number(purchase.agreed_price);\n    const split = computePlatformFeeSplit({\n      paymentKind: \"buy\",\n      amount: agreed,\n      currency: (purchase.currency ?? \"USD\") || \"USD\",\n    });\n    return { purchase, alreadyPaid: true, platformFee: split.platformFee, sellerNet: split.payeeNet };\n  }/s
' "$FILE"

# ------------------------------------------------------------
# Patch 2: remove unsafe "status=paid" enum probe + broken UPDATE
#          (your current code has invalid placeholders: id = ::uuid)
# ------------------------------------------------------------
perl -0777 -i -pe '
  s/\n\s*\/\/ 3\)\s*Optionally advance purchase status \(SAFE\)\.[\s\S]*?\n\s*\}\n\s*\n/\n/s
' "$FILE"

# ------------------------------------------------------------
# Patch 3: extend PropertyPurchaseRow + SELECT to include milestone fields
# ------------------------------------------------------------
# Add fields to type (only if not already present)
perl -0777 -i -pe '
  if ($t !~ /payment_status:\s*string;/) {
    $t =~ s/deleted_at:\s*string\s*\|\s*null;\s*\n/ deleted_at: string | null;\n  payment_status: string;\n  paid_at: string | null;\n  paid_amount: string | null;\n  last_payment_id: string | null;\n/s;
  }
' "$FILE"

# Add columns to PURCHASE_SELECT (only if not already present)
perl -0777 -i -pe '
  if ($t !~ /payment_status::text AS payment_status/) {
    $t =~ s/deleted_at::text AS deleted_at\s*\n/deleted_at::text AS deleted_at,\n  payment_status::text AS payment_status,\n  paid_at::text AS paid_at,\n  paid_amount::text AS paid_amount,\n  last_payment_id::text AS last_payment_id\n/s;
  }
' "$FILE"

# ------------------------------------------------------------
# Patch 4: update milestone fields after successful ledger credits
#   - payment_status = paid
#   - paid_at set if null
#   - paid_amount set to full amount
#   - last_payment_id taken from latest property_purchase_payments link
# ------------------------------------------------------------
# Insert the milestone UPDATE right after the second credit (creditPayee)
perl -0777 -i -pe '
  if ($t !~ /Update purchase payment milestones/) {
    $t =~ s/(\/\/ 2\)\s*credit seller net[\s\S]*?await creditPayee\([\s\S]*?\);\s*)/\1\n  \/\/ 3) Update purchase payment milestones (no lifecycle enum change)\n  const lastPay = await client.query<{ payment_id: string }>(\n    `\n    SELECT payment_id::text AS payment_id\n    FROM public.property_purchase_payments\n    WHERE organization_id = $1::uuid\n      AND purchase_id = $2::uuid\n    ORDER BY created_at DESC\n    LIMIT 1;\n    `,\n    [args.organizationId, purchase.id]\n  );\n\n  const lastPaymentId = lastPay.rows?.[0]?.payment_id || null;\n\n  await client.query(\n    `\n    UPDATE public.property_purchases\n    SET payment_status = \'paid\'::purchase_payment_status,\n        paid_at = COALESCE(paid_at, NOW()),\n        paid_amount = $1::numeric,\n        last_payment_id = COALESCE($2::uuid, last_payment_id),\n        updated_at = NOW()\n    WHERE id = $3::uuid\n      AND organization_id = $4::uuid\n      AND deleted_at IS NULL;\n    `,\n    [amount, lastPaymentId, purchase.id, args.organizationId]\n  );\n/s;
  }
' "$FILE"

# ------------------------------------------------------------
# Quick sanity: fail if the old broken placeholders still exist
# ------------------------------------------------------------
if grep -n "WHERE id = ::uuid" "$FILE" >/dev/null 2>&1; then
  echo "❌ Patch incomplete: still found invalid 'WHERE id = ::uuid' in $FILE"
  exit 1
fi

echo "✅ PATCHED: $FILE"
echo ""
echo "NEXT:"
echo "  1) Restart server: npm run dev"
echo "  2) Call pay endpoint again (should be idempotent)"
echo "  3) Verify milestones:"
echo "     PAGER=cat psql -d \"\$DB_NAME\" -X -c \"select id, status, payment_status, paid_at, paid_amount, last_payment_id from public.property_purchases where id='\$PURCHASE_ID'::uuid;\""
