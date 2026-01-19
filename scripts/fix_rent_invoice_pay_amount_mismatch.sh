#!/usr/bin/env bash
set -euo pipefail

echo "== Fix rent invoice PAY: stop using payments/listing price guard; mark invoice paid =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/src/services/rent_invoices.service.ts"

mkdir -p "$(dirname "$FILE")"

cat > "$FILE" <<'TS'
import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";
import {
  findRentInvoiceByTenancyPeriod,
  insertRentInvoice,
  listRentInvoices,
} from "../repos/rent_invoices.repo.js";

type TenancyMini = {
  id: string;
  tenant_id: string;
  property_id: string;
  rent_amount: string;
};

type RentInvoiceRow = {
  id: string;
  organization_id: string;
  tenancy_id: string;
  tenant_id: string;
  property_id: string;
  invoice_number: string | number | null;
  status: InvoiceStatus;
  period_start: string;
  period_end: string;
  due_date: string;
  subtotal: string;
  late_fee_amount: string | null;
  total_amount: string;
  currency: string | null;
  paid_amount: string | null;
  paid_at: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
  deleted_at: string | null;
};

const RENT_INVOICE_SELECT = `
  id,
  organization_id,
  tenancy_id,
  tenant_id,
  property_id,
  invoice_number,
  status,
  period_start::text AS period_start,
  period_end::text AS period_end,
  due_date::text AS due_date,
  subtotal::text AS subtotal,
  late_fee_amount::text AS late_fee_amount,
  total_amount::text AS total_amount,
  currency,
  paid_amount::text AS paid_amount,
  paid_at::text AS paid_at,
  notes,
  created_at::text AS created_at,
  updated_at::text AS updated_at,
  deleted_at::text AS deleted_at
`;

// ------------------------------------
// LIST
// ------------------------------------
export async function getRentInvoices(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    tenancyId?: string;
    tenantId?: string;
    propertyId?: string;
    status?: InvoiceStatus;
  }
) {
  return listRentInvoices(client, {
    limit: args.limit,
    offset: args.offset,
    tenancy_id: args.tenancyId,
    tenant_id: args.tenantId,
    property_id: args.propertyId,
    status: args.status,
  });
}

// ------------------------------------
// GENERATE (idempotent per tenancy+period)
// ------------------------------------
export async function generateRentInvoiceForTenancy(
  client: PoolClient,
  args: {
    tenancyId: string;
    periodStart: string;
    periodEnd: string;
    dueDate: string;

    subtotal?: number;
    lateFeeAmount?: number | null;
    currency?: string | null;
    status?: InvoiceStatus | null;
    notes?: string | null;
  }
): Promise<{ row: any; reused: boolean }> {
  const existing = await findRentInvoiceByTenancyPeriod(client, {
    tenancy_id: args.tenancyId,
    period_start: args.periodStart,
    period_end: args.periodEnd,
    due_date: args.dueDate,
  });
  if (existing) return { row: existing, reused: true };

  const { rows } = await client.query<TenancyMini>(
    `
    SELECT
      id,
      tenant_id,
      property_id,
      rent_amount::text AS rent_amount
    FROM public.tenancies
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.tenancyId]
  );

  const tenancy = rows[0];
  if (!tenancy) {
    const e: any = new Error("Tenancy not found");
    e.code = "TENANCY_NOT_FOUND";
    throw e;
  }

  const subtotal = typeof args.subtotal === "number" ? args.subtotal : Number(tenancy.rent_amount);
  const lateFee = args.lateFeeAmount == null ? 0 : Number(args.lateFeeAmount);
  const total = subtotal + lateFee;

  const currency = (args.currency ?? "USD") || "USD";
  const status: InvoiceStatus = (args.status ?? "issued") || "issued";

  const row = await insertRentInvoice(client, {
    tenancy_id: args.tenancyId,
    tenant_id: tenancy.tenant_id,
    property_id: tenancy.property_id,

    period_start: args.periodStart,
    period_end: args.periodEnd,
    due_date: args.dueDate,

    subtotal,
    late_fee_amount: lateFee,
    total_amount: total,

    currency,
    status,
    notes: args.notes ?? null,
  });

  return { row, reused: false };
}

// ------------------------------------
// PAY (IMPORTANT FIX)
// We DO NOT create a row in `payments` because your DB enforces:
// payments.amount == listing.listed_price
// Rent invoice payments must instead match invoice.total_amount.
// So we mark rent_invoices as paid.
// ------------------------------------
export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string; // currently unused in DB (kept for API)
    amount?: number | null;
  }
): Promise<RentInvoiceRow> {
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

  // Idempotent: if already paid, return as-is
  if (invoice.status === "paid") return invoice;

  const total = Number(invoice.total_amount);
  const amount = typeof args.amount === "number" ? args.amount : total;

  // Guard: amount must match invoice total
  if (Number(amount) !== Number(total)) {
    const e: any = new Error(`Payment.amount (${amount}) must equal invoice.total_amount (${invoice.total_amount})`);
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

  return updRes.rows[0]!;
}
TS

echo "✅ Wrote: src/services/rent_invoices.service.ts (PAY now marks invoice paid; no payments/listing guard)"
echo "➡️ Restart server: npm run dev"
