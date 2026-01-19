#!/usr/bin/env bash
set -euo pipefail

echo "=== Fix: permanent purchase reconcile in paystack_finalize.service.ts ==="

FILE="src/services/paystack_finalize.service.ts"
test -f "$FILE" || { echo "❌ Missing $FILE"; exit 1; }

TS="$(date +%s)"
cp -a "$FILE" "$FILE.bak.$TS"
echo "Backup: $FILE.bak.$TS"

# Insert helper functions near the top (after approxEqual or before finalize export).
# We’ll only insert if not already present.
if ! rg -n "ensurePurchasePaymentLink\\(" "$FILE" >/dev/null 2>&1; then
  perl -0777 -i -pe 's@(function approxEqual\\([\\s\\S]*?\\}\\n)@$1\nasync function ensurePurchasePaymentLink(\n  client: PoolClient,\n  args: { organizationId: string; purchaseId: string; paymentId: string; amountMajor: number }\n) {\n  await client.query(\n    `\n    insert into public.property_purchase_payments (organization_id, purchase_id, payment_id, amount)\n    values ($1::uuid, $2::uuid, $3::uuid, $4::numeric)\n    on conflict (purchase_id, payment_id) do nothing;\n    `,\n    [args.organizationId, args.purchaseId, args.paymentId, args.amountMajor]\n  );\n}\n\nasync function reconcilePurchaseFromLinks(\n  client: PoolClient,\n  args: { organizationId: string; purchaseId: string }\n): Promise<{ ok: true } | { ok: false; error: string; message?: string }> {\n  const { rows } = await client.query<{\n    agreed_price: string;\n    paid_total: string;\n    last_payment_id: string | null;\n  }>(\n    `\n    with agg as (\n      select\n        pp.agreed_price::text as agreed_price,\n        coalesce(sum(ppp.amount),0)::text as paid_total,\n        (\n          select ppp2.payment_id::text\n          from public.property_purchase_payments ppp2\n          where ppp2.purchase_id = pp.id\n          order by ppp2.created_at desc\n          limit 1\n        ) as last_payment_id\n      from public.property_purchases pp\n      left join public.property_purchase_payments ppp on ppp.purchase_id = pp.id\n      where pp.id = $1::uuid\n        and pp.organization_id = $2::uuid\n        and pp.deleted_at is null\n      group by pp.id\n    )\n    select * from agg;\n    `,\n    [args.purchaseId, args.organizationId]\n  );\n\n  const a = rows?.[0];\n  if (!a) return { ok: false, error: \"PURCHASE_NOT_FOUND\" };\n\n  const agreed = Number(a.agreed_price);\n  const paidTotal = Number(a.paid_total);\n  if (!Number.isFinite(agreed) || agreed <= 0) return { ok: false, error: \"INVALID_PURCHASE_PRICE\" };\n  if (!Number.isFinite(paidTotal) || paidTotal < 0) return { ok: false, error: \"INVALID_PAID_TOTAL\" };\n\n  const nextStatus =\n    paidTotal >= agreed ? \"paid\" :\n    paidTotal > 0 ? \"partially_paid\" :\n    \"unpaid\";\n\n  await client.query(\n    `\n    update public.property_purchases\n    set\n      paid_amount = nullif($3::numeric, 0),\n      payment_status = $4::purchase_payment_status,\n      last_payment_id = $5::uuid,\n      paid_at = case when $3::numeric > 0 then coalesce(paid_at, now()) else paid_at end,\n      updated_at = now()\n    where id = $1::uuid\n      and organization_id = $2::uuid\n      and deleted_at is null;\n    `,\n    [args.purchaseId, args.organizationId, paidTotal, nextStatus, a.last_payment_id]\n  );\n\n  return { ok: true };\n}\n\n@smg' "$FILE"
  echo "✅ Inserted helper functions"
else
  echo "ℹ️ Helpers already exist, skipping insert"
fi

# Now patch PURCHASE branch to ALWAYS run ensure link + reconcile
# We replace the first "if (payment.reference_type === \"purchase\" ..." block body carefully.
perl -0777 -i -pe 's@
if \\(payment\\.reference_type === \"purchase\" && payment\\.reference_id\\) \\{
([\\s\\S]*?)
return \\{ ok: true \\ };
\\}
@
if (payment.reference_type === \"purchase\" && payment.reference_id) {
    // Always mark payment successful (idempotent), ensure link exists, and reconcile purchase aggregates
    await client.query(
      `
      update public.payments
      set
        status = '\''successful'\''::public.payment_status,
        completed_at = now(),
        gateway_transaction_id = coalesce(gateway_transaction_id, $2::text),
        gateway_response = coalesce(gateway_response, $3::jsonb),
        currency = coalesce(currency, $4::text),
        updated_at = now()
      where id = $1::uuid
        and deleted_at is null;
      `,
      [payment.id, String(evt.data?.id ?? \"\"), JSON.stringify(evt), currency]
    );

    // Ensure property_purchase_payments link exists (source of truth for purchase totals)
    await ensurePurchasePaymentLink(client, {
      organizationId: orgId,
      purchaseId: payment.reference_id,
      paymentId: payment.id,
      amountMajor,
    });

    // Reconcile property_purchases from property_purchase_payments
    const rec = await reconcilePurchaseFromLinks(client, {
      organizationId: orgId,
      purchaseId: payment.reference_id,
    });
    if (!rec.ok) return rec;

    // Escrow hold (safe: function expects new total; escrow_held_amount already enforced elsewhere)
    const resEscrow = await finalizePurchaseEscrowFunding(client, {
      organizationId: orgId,
      purchaseId: payment.reference_id,
      amountMajor,
      currency,
      paymentId: payment.id,
      note: `paystack:charge.success:${reference}`,
    });
    if (!resEscrow.ok) return resEscrow;

    return { ok: true };
}
@smg' "$FILE"

echo "✅ Patched PURCHASE finalize branch"

echo
echo "---- compile check ----"
npx tsc -p tsconfig.json --noEmit
echo "✅ tsc OK"

echo
echo "---- sanity grep ----"
rg -n "ensurePurchasePaymentLink\\(|reconcilePurchaseFromLinks\\(" "$FILE" | head -n 20

echo "=== DONE ==="
