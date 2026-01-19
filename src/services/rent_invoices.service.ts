import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";
import { computePlatformFeeSplit } from "../config/fees.config.js";
import { creditPlatformFee, creditPayee } from "./ledger.service.js";

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

/**
 * PAYEE RESOLUTION
 * Uses: properties.owner_id as payee user id
 */
async function resolveRentInvoicePayeeUserId(
  client: PoolClient,
  invoiceId: string,
  organizationId: string
): Promise<string> {
  const r = await client.query<{ payee_user_id: string }>(
    `
    SELECT p.owner_id AS payee_user_id
    FROM public.rent_invoices ri
    JOIN public.properties p ON p.id = ri.property_id
    WHERE ri.id = $1::uuid
      AND ri.organization_id = $2::uuid
      AND ri.deleted_at IS NULL
    LIMIT 1;
    `,
    [invoiceId, organizationId]
  );

  const payee = r.rows[0]?.payee_user_id;
  if (!payee) throw new Error("Cannot resolve payee_user_id for invoice " + invoiceId);
  return payee;
}

function round2(n: number): number {
  // numeric(15,2) friendly rounding
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

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

export async function generateRentInvoiceForTenancy(
  client: PoolClient,
  args: {
    organizationId: string;
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
    organization_id: args.organizationId,
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

/**
 * PAY
 * - Idempotent: if invoice already paid => return alreadyPaid=true, no duplicate rows
 * - Creates:
 *    public.rent_payments
 *    public.rent_invoice_payments
 *    public.wallet_transactions:
 *        - credit_payee (NET) to payee wallet
 *        - credit_platform_fee (FEE) to platform wallet
 * - Then marks invoice paid.
 */
export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string;
    amount?: number | null;
  }
): Promise<{ row: RentInvoiceRow; alreadyPaid: boolean }> {
  // 1) Load invoice
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

  // Idempotent short-circuit
  if (invoice.status === "paid") {
    return { row: invoice, alreadyPaid: true };
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

  const currency = (invoice.currency ?? "USD") || "USD";
  const method = args.paymentMethod || "card";

  // 2) Create rent_payments
  const rpRes = await client.query<{ id: string }>(
    `
    INSERT INTO public.rent_payments (
      organization_id,
      tenancy_id,
      invoice_id,
      tenant_id,
      property_id,
      amount,
      currency,
      payment_method
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::uuid,
      $4::uuid,
      $5::uuid,
      $6::numeric,
      $7::text,
      $8::text
    )
    RETURNING id;
    `,
    [
      invoice.organization_id,
      invoice.tenancy_id,
      invoice.id,
      invoice.tenant_id,
      invoice.property_id,
      amount,
      currency,
      method,
    ]
  );

  const rentPaymentId = rpRes.rows[0]?.id;
  if (!rentPaymentId) {
    const e: any = new Error("Failed to create rent_payment");
    e.code = "RENT_PAYMENT_CREATE_FAILED";
    throw e;
  }

  // 3) Link rent_invoice_payments (idempotent)
  await client.query(
    `
    INSERT INTO public.rent_invoice_payments (
      organization_id,
      invoice_id,
      rent_payment_id,
      amount
    )
    VALUES ($1::uuid, $2::uuid, $3::uuid, $4::numeric)
    ON CONFLICT DO NOTHING;
    `,
    [invoice.organization_id, invoice.id, rentPaymentId, amount]
  );
  // 4) Split platform fee + payee net, then credit wallets (centralized logic)

  // 4) Split platform fee (2.5%) + credit wallets (SINGLE SOURCE OF TRUTH)
  const split = computePlatformFeeSplit({
    paymentKind: "rent",
    amount,
    currency,
  });

  // Resolve payee (landlord/owner) and credit net
  const payeeUserId = await resolveRentInvoicePayeeUserId(
    client,
    invoice.id,
    invoice.organization_id
  );

  await creditPayee(client, {
    organizationId: invoice.organization_id,
    payeeUserId,
    referenceType: "rent_invoice",
    referenceId: invoice.id,
    amount: split.payeeNet,
    currency,
    note: `Rent net (after ${split.pctUsed}% fee) for invoice ${invoice.invoice_number ?? invoice.id}`,
  });

  // Credit platform fee into platform wallet
  await creditPlatformFee(client, {
    organizationId: invoice.organization_id,
    referenceType: "rent_invoice",
    referenceId: invoice.id,
    amount: split.platformFee,
    currency,
    note: `Platform fee (${split.pctUsed}%) for invoice ${invoice.invoice_number ?? invoice.id}`,
  });




  // 5) Mark invoice paid (paid_amount is FULL amount paid)
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
    [invoice.id, amount]
  );

  return { row: updRes.rows[0]!, alreadyPaid: false };
}