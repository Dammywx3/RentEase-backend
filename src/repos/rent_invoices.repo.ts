import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";

export async function listRentInvoices(
  client: PoolClient,
  args: {
    limit: number;
    offset: number;
    tenancy_id?: string;
    tenant_id?: string;
    property_id?: string;
    status?: InvoiceStatus;
  }
) {
  const where: string[] = ["deleted_at IS NULL"];
  const params: any[] = [];
  let i = 1;

  if (args.tenancy_id) { where.push(`tenancy_id = $${i++}::uuid`); params.push(args.tenancy_id); }
  if (args.tenant_id)  { where.push(`tenant_id  = $${i++}::uuid`); params.push(args.tenant_id); }
  if (args.property_id){ where.push(`property_id= $${i++}::uuid`); params.push(args.property_id); }
  if (args.status)     { where.push(`status = $${i++}::invoice_status`); params.push(args.status); }

  params.push(args.limit, args.offset);

  const sql = `
    SELECT *
    FROM public.rent_invoices
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${i++} OFFSET $${i++};
  `;

  const { rows } = await client.query(sql, params);
  return rows;
}

export async function findRentInvoiceByTenancyPeriod(
  client: PoolClient,
  args: {
    tenancy_id: string;
    period_start: string;
    period_end: string;
    due_date: string;
  }
) {
  const { rows } = await client.query(
    `
    SELECT *
    FROM public.rent_invoices
    WHERE tenancy_id = $1::uuid
      AND period_start = $2::date
      AND period_end   = $3::date
      AND due_date     = $4::date
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.tenancy_id, args.period_start, args.period_end, args.due_date]
  );
  return rows[0] ?? null;
}

export async function insertRentInvoice(
  client: PoolClient,
  args: {
    organization_id: string;          // ✅ REQUIRED NOW
    tenancy_id: string;
    tenant_id: string;
    property_id: string;
    period_start: string;
    period_end: string;
    due_date: string;
    subtotal: number;
    late_fee_amount: number;
    total_amount: number;
    currency: string;
    status: InvoiceStatus;
    notes?: string | null;
  }
) {
  const { rows } = await client.query(
    `
    INSERT INTO public.rent_invoices (
      organization_id,
      tenancy_id,
      tenant_id,
      property_id,
      period_start,
      period_end,
      due_date,
      subtotal,
      late_fee_amount,
      total_amount,
      currency,
      status,
      notes
    ) VALUES (
      $1::uuid,
      $2::uuid,
      $3::uuid,
      $4::uuid,
      $5::date,
      $6::date,
      $7::date,
      $8::numeric,
      $9::numeric,
      $10::numeric,
      $11::text,
      $12::invoice_status,
      $13::text
    )
    RETURNING *;
    `,
    [
      args.organization_id,
      args.tenancy_id,
      args.tenant_id,
      args.property_id,
      args.period_start,
      args.period_end,
      args.due_date,
      args.subtotal,
      args.late_fee_amount,
      args.total_amount,
      args.currency,
      args.status,
      args.notes ?? null,
    ]
  );

  return rows[0]!;
}
