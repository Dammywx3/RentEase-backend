#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SVC="$ROOT/src/services/rent_invoices.service.ts"

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$SVC" ]; then
  echo "❌ Missing file: $SVC"
  exit 1
fi

cp "$SVC" "$ROOT/scripts/.bak/rent_invoices.service.ts.bak.$ts"
echo "✅ backup -> scripts/.bak/rent_invoices.service.ts.bak.$ts"

perl -0777 -i -pe '
  my $replacement = q{
export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string; // currently unused in DB (kept for API)
    amount?: number | null;
  }
): Promise<{ row: RentInvoiceRow; alreadyPaid: boolean }> {
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

  // Idempotent: if already paid, return flag=true
  if (invoice.status === "paid") {
    return { row: invoice, alreadyPaid: true };
  }

  const total = Number(invoice.total_amount);
  const amount = typeof args.amount === "number" ? args.amount : total;

  // Guard: amount must match invoice total
  if (Number(amount) !== Number(total)) {
    const e: any = new Error(
      `Payment.amount (${amount}) must equal invoice.total_amount (${invoice.total_amount})`
    );
    e.code = "AMOUNT_MISMATCH";
    throw e;
  }

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

  return { row: updRes.rows[0]!, alreadyPaid: false };
}
};

  s/export\s+async\s+function\s+payRentInvoice\s*\([\s\S]*?\n\}\n/$replacement\n/s
    or die "❌ Could not find payRentInvoice() function to replace in $ARGV\n";
' "$SVC"

echo "✅ Patched: src/services/rent_invoices.service.ts"
echo "➡️ Restart server: npm run dev"
