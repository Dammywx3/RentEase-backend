#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BAK="$ROOT/scripts/.bak"
mkdir -p "$BAK"
ts="$(date +%Y%m%d_%H%M%S)"

SVC="$ROOT/src/services/rent_invoices.service.ts"
if [[ ! -f "$SVC" ]]; then
  echo "ERROR: missing $SVC"
  exit 1
fi

cp "$SVC" "$BAK/rent_invoices.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$ts"

# Patch payRentInvoice() by replacing it entirely (safe/clean)
perl -0777 -i -pe '
  s/export\s+async\s+function\s+payRentInvoice\s*\([\s\S]*?\n}\s*$/export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string; // stored in rent_payments
    amount?: number | null;
  }
): Promise<{ row: RentInvoiceRow; alreadyPaid: boolean; rentPaymentId: string }> {
  // Load invoice
  const invRes = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.invoiceId]
  );

  const invoice = invRes.rows[0];
  if (!invoice) {
    const e: any = new Error("Invoice not found");
    e.code = "INVOICE_NOT_FOUND";
    throw e;
  }

  // Idempotent: if already paid, return and do not create another payment row
  if (invoice.status === "paid") {
    // try to find the last rent_payment linked to this invoice (optional)
    const rp = await client.query<{ rent_payment_id: string }>(
      `SELECT rent_payment_id FROM public.rent_invoice_payments WHERE invoice_id = $1::uuid ORDER BY created_at DESC LIMIT 1;`,
      [args.invoiceId]
    );
    return {
      row: invoice,
      alreadyPaid: true,
      rentPaymentId: rp.rows[0]?.rent_payment_id ?? "",
    };
  }

  const total = Number(invoice.total_amount);
  const amount = typeof args.amount === "number" ? args.amount : total;

  if (Number(amount) !== Number(total)) {
    const e: any = new Error(
      `Payment.amount (${amount}) must equal invoice.total_amount (${invoice.total_amount})`
    );
    e.code = "AMOUNT_MISMATCH";
    throw e;
  }

  // 1) create rent_payment
  const payRes = await client.query<{
    id: string;
  }>(
    `
    INSERT INTO public.rent_payments (invoice_id, amount, currency, payment_method)
    VALUES ($1::uuid, $2::numeric, COALESCE($3, 'USD'), $4::text)
    RETURNING id;
    `,
    [args.invoiceId, amount, invoice.currency, args.paymentMethod || "unknown"]
  );

  const rentPaymentId = payRes.rows[0]?.id;
  if (!rentPaymentId) {
    const e: any = new Error("Failed to create rent_payment");
    e.code = "RENT_PAYMENT_CREATE_FAILED";
    throw e;
  }

  // 2) link invoice -> rent_payment
  await client.query(
    `
    INSERT INTO public.rent_invoice_payments (invoice_id, rent_payment_id, amount)
    VALUES ($1::uuid, $2::uuid, $3::numeric)
    ON CONFLICT (invoice_id, rent_payment_id) DO NOTHING;
    `,
    [args.invoiceId, rentPaymentId, amount]
  );

  // 3) mark invoice paid
  const updRes = await client.query<RentInvoiceRow>(
    `
    UPDATE public.rent_invoices
    SET
      status = '\''paid'\''::invoice_status,
      paid_amount = $2::numeric,
      paid_at = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [args.invoiceId, amount]
  );

  const updated = updRes.rows[0]!;
  // 4) wallet transaction credit (best-effort)
  // Find or create tenant wallet account (non-platform)
  const waRes = await client.query<{ id: string }>(
    `
    SELECT id
    FROM public.wallet_accounts
    WHERE organization_id = current_organization_uuid()
      AND user_id = $1::uuid
      AND currency = COALESCE($2, 'USD')
      AND is_platform_wallet = false
    LIMIT 1;
    `,
    [updated.tenant_id, updated.currency]
  );

  let walletAccountId = waRes.rows[0]?.id;

  if (!walletAccountId) {
    const waIns = await client.query<{ id: string }>(
      `
      INSERT INTO public.wallet_accounts (user_id, currency, is_platform_wallet)
      VALUES ($1::uuid, COALESCE($2, 'USD'), false)
      RETURNING id;
      `,
      [updated.tenant_id, updated.currency]
    );
    walletAccountId = waIns.rows[0]?.id;
  }

  if (walletAccountId) {
    // txn_type must be a valid enum in your DB; try credit first, fallback deposit
    try {
      await client.query(
        `
        INSERT INTO public.wallet_transactions
          (wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note)
        VALUES
          ($1::uuid, 'credit'::wallet_transaction_type, 'rent_invoice', $2::uuid, $3::numeric, COALESCE($4,'USD'), $5::text);
        `,
        [
          walletAccountId,
          updated.id,
          amount,
          updated.currency,
          `Rent invoice payment ${updated.invoice_number ?? updated.id}`,
        ]
      );
    } catch (e1) {
      // fallback if enum has different value
      await client.query(
        `
        INSERT INTO public.wallet_transactions
          (wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note)
        VALUES
          ($1::uuid, 'deposit'::wallet_transaction_type, 'rent_invoice', $2::uuid, $3::numeric, COALESCE($4,'USD'), $5::text);
        `,
        [
          walletAccountId,
          updated.id,
          amount,
          updated.currency,
          `Rent invoice payment ${updated.invoice_number ?? updated.id}`,
        ]
      );
    }
  }

  return { row: updated, alreadyPaid: false, rentPaymentId };
}
\n/smg' "$SVC"

echo "✅ patched: src/services/rent_invoices.service.ts"

# Quick grep sanity
echo "---- sanity"
grep -n "INSERT INTO public.rent_payments" -n "$SVC" >/dev/null && echo "✅ rent_payments insert found"
grep -n "rent_invoice_payments" -n "$SVC" >/dev/null && echo "✅ rent_invoice_payments link found"
grep -n "wallet_transactions" -n "$SVC" >/dev/null && echo "✅ wallet_transactions insert found"

echo ""
echo "== DONE =="
echo "➡️ Restart server: npm run dev"
