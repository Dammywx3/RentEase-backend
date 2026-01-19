#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC="$ROOT/src/services/rent_invoices.service.ts"
BAK="$ROOT/scripts/.bak"
mkdir -p "$BAK"
ts="$(date +%Y%m%d_%H%M%S)"

if [[ ! -f "$SVC" ]]; then
  echo "ERROR: missing $SVC"
  exit 1
fi

cp "$SVC" "$BAK/rent_invoices.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$ts"

python3 - <<'PY'
from pathlib import Path
import re

svc = Path("src/services/rent_invoices.service.ts")
txt = svc.read_text(encoding="utf-8")

# Replace entire payRentInvoice() function (any implementation) with a known-good one.
# We match from the function signature to the closing brace of the function.
pat = re.compile(r"""
export\s+async\s+function\s+payRentInvoice\s*\(
[\s\S]*?
\}\s*$
""", re.VERBOSE)

new_fn = r"""export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string;
    amount?: number | null;
  }
): Promise<{ row: RentInvoiceRow; alreadyPaid: boolean; rentPaymentId?: string }> {
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

  // Idempotent: if already paid, return invoice + last rent_payment (if any)
  if (invoice.status === "paid") {
    const rp = await client.query<{ rent_payment_id: string }>(
      `
      SELECT rent_payment_id
      FROM public.rent_invoice_payments
      WHERE invoice_id = $1::uuid
      ORDER BY created_at DESC
      LIMIT 1;
      `,
      [args.invoiceId]
    );

    return { row: invoice, alreadyPaid: true, rentPaymentId: rp.rows[0]?.rent_payment_id };
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

  // 1) Create rent_payment (NOT payments table)
  const payRes = await client.query<{ id: string }>(
    `
    INSERT INTO public.rent_payments (invoice_id, amount, currency, payment_method)
    VALUES ($1::uuid, $2::numeric, COALESCE($3, 'USD'), COALESCE($4, 'unknown'))
    RETURNING id;
    `,
    [args.invoiceId, amount, invoice.currency, args.paymentMethod]
  );

  const rentPaymentId = payRes.rows[0]?.id;
  if (!rentPaymentId) {
    const e: any = new Error("Failed to create rent_payment");
    e.code = "RENT_PAYMENT_CREATE_FAILED";
    throw e;
  }

  // 2) Link invoice -> rent_payment
  await client.query(
    `
    INSERT INTO public.rent_invoice_payments (invoice_id, rent_payment_id, amount)
    VALUES ($1::uuid, $2::uuid, $3::numeric)
    ON CONFLICT (invoice_id, rent_payment_id) DO NOTHING;
    `,
    [args.invoiceId, rentPaymentId, amount]
  );

  // 3) Mark invoice paid
  const updRes = await client.query<RentInvoiceRow>(
    `
    UPDATE public.rent_invoices
    SET
      status = 'paid'::invoice_status,
      paid_amount = $2::numeric,
      paid_at = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [args.invoiceId, amount]
  );

  const updated = updRes.rows[0]!;

  // 4) Wallet tx (best-effort)
  try {
    // Find tenant wallet (non-platform). Create if missing.
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
      const note = `Rent invoice payment ${updated.invoice_number ?? updated.id}`;

      // Some schemas use txn_type: 'credit', others use 'deposit'
      try {
        await client.query(
          `
          INSERT INTO public.wallet_transactions
            (wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note)
          VALUES
            ($1::uuid, 'credit'::wallet_transaction_type, 'rent_invoice', $2::uuid, $3::numeric, COALESCE($4,'USD'), $5::text);
          `,
          [walletAccountId, updated.id, amount, updated.currency, note]
        );
      } catch {
        await client.query(
          `
          INSERT INTO public.wallet_transactions
            (wallet_account_id, txn_type, reference_type, reference_id, amount, currency, note)
          VALUES
            ($1::uuid, 'deposit'::wallet_transaction_type, 'rent_invoice', $2::uuid, $3::numeric, COALESCE($4,'USD'), $5::text);
          `,
          [walletAccountId, updated.id, amount, updated.currency, note]
        );
      }
    }
  } catch {
    // ignore wallet failures (do not block invoice payment)
  }

  return { row: updated, alreadyPaid: false, rentPaymentId };
}
"""

new_txt, n = pat.subn(new_fn, txt, count=1)
if n == 0:
  # If the function isn't at the bottom, do a broader match
  pat2 = re.compile(r"export\s+async\s+function\s+payRentInvoice\s*\([\s\S]*?\n\}\n", re.M)
  new_txt, n2 = pat2.subn(new_fn + "\n", txt, count=1)
  if n2 == 0:
    raise SystemExit("ERROR: Could not find payRentInvoice() in src/services/rent_invoices.service.ts")

svc.write_text(new_txt, encoding="utf-8")
print("✅ patched payRentInvoice() safely")
PY

echo "---- sanity checks"
grep -n "INSERT INTO public.rent_payments" "$SVC" >/dev/null && echo "✅ rent_payments insert found"
grep -n "rent_invoice_payments" "$SVC" >/dev/null && echo "✅ rent_invoice_payments link found"
grep -n "wallet_transactions" "$SVC" >/dev/null && echo "✅ wallet_transactions insert found"

echo ""
echo "== DONE =="
echo "➡️ Restart server: npm run dev"
