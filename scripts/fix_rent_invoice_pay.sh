#!/usr/bin/env bash
set -euo pipefail

echo "== Rent invoice PAY endpoint fix =="

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ----------------------------
# 1) Schema: add Pay body schema + export types cleanly
# ----------------------------
cat > src/schemas/rent_invoices.schema.ts <<'TS'
import { z } from "zod";

export const InvoiceStatusSchema = z.enum([
  "draft",
  "issued",
  "paid",
  "overdue",
  "void",
  "cancelled",
]);
export type InvoiceStatus = z.infer<typeof InvoiceStatusSchema>;

export const PaymentMethodSchema = z.enum(["card", "bank_transfer", "wallet"]);
export type PaymentMethod = z.infer<typeof PaymentMethodSchema>;

export const RentInvoiceRowSchema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid(),
  tenancy_id: z.string().uuid(),
  tenant_id: z.string().uuid(),
  property_id: z.string().uuid(),

  invoice_number: z.coerce.number().int().nullable().optional(),
  status: InvoiceStatusSchema,

  period_start: z.string(), // YYYY-MM-DD
  period_end: z.string(),   // YYYY-MM-DD
  due_date: z.string(),     // YYYY-MM-DD

  subtotal: z.string(),
  late_fee_amount: z.string().nullable().optional(),
  total_amount: z.string(),

  currency: z.string().length(3).nullable().optional(),
  paid_amount: z.string().nullable().optional(),
  paid_at: z.string().nullable().optional(),

  notes: z.string().nullable().optional(),

  created_at: z.string(),
  updated_at: z.string(),
  deleted_at: z.string().nullable(),
});

export const ListRentInvoicesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(20),
  offset: z.coerce.number().int().min(0).default(0),
  tenancyId: z.string().uuid().optional(),
  tenantId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  status: InvoiceStatusSchema.optional(),
});

export const GenerateRentInvoiceBodySchema = z.object({
  periodStart: z.string(), // YYYY-MM-DD
  periodEnd: z.string(),   // YYYY-MM-DD
  dueDate: z.string(),     // YYYY-MM-DD

  subtotal: z.number().positive().optional(),
  lateFeeAmount: z.number().nonnegative().nullable().optional(),
  currency: z.string().length(3).nullable().optional(),
  status: InvoiceStatusSchema.nullable().optional(),
  notes: z.string().nullable().optional(),
});

export const PayRentInvoiceBodySchema = z.object({
  paymentMethod: PaymentMethodSchema,
  // If omitted, we pay the remaining balance.
  amount: z.number().positive().optional(),
});
TS

echo "✅ wrote src/schemas/rent_invoices.schema.ts"


# ----------------------------
# 2) Repo: add helpers for invoice fetch/update
# ----------------------------
cat > src/repos/rent_invoices.repo.ts <<'TS'
import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";

export type RentInvoiceRow = {
  id: string;
  organization_id: string;
  tenancy_id: string;
  tenant_id: string;
  property_id: string;

  invoice_number: number | null;
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

export async function getRentInvoiceById(
  client: PoolClient,
  invoiceId: string
): Promise<RentInvoiceRow | null> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [invoiceId]
  );
  return rows[0] ?? null;
}

export async function getRentInvoiceByIdForUpdate(
  client: PoolClient,
  invoiceId: string
): Promise<RentInvoiceRow | null> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    FOR UPDATE;
    `,
    [invoiceId]
  );
  return rows[0] ?? null;
}

export async function findRentInvoiceByTenancyPeriod(
  client: PoolClient,
  args: {
    tenancy_id: string;
    period_start: string;
    period_end: string;
    due_date: string;
  }
): Promise<RentInvoiceRow | null> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE deleted_at IS NULL
      AND tenancy_id = $1
      AND period_start = $2::date
      AND period_end = $3::date
      AND due_date = $4::date
    ORDER BY created_at DESC
    LIMIT 1;
    `,
    [args.tenancy_id, args.period_start, args.period_end, args.due_date]
  );
  return rows[0] ?? null;
}

export async function insertRentInvoice(
  client: PoolClient,
  args: {
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
): Promise<RentInvoiceRow> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    INSERT INTO public.rent_invoices (
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
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::uuid,
      $4::date,
      $5::date,
      $6::date,
      $7::numeric,
      $8::numeric,
      $9::numeric,
      $10::varchar(3),
      $11::invoice_status,
      $12::text
    )
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [
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
): Promise<RentInvoiceRow[]> {
  const where: string[] = ["deleted_at IS NULL"];
  const params: any[] = [];
  let i = 1;

  if (args.tenancy_id) {
    where.push(`tenancy_id = $${i++}::uuid`);
    params.push(args.tenancy_id);
  }
  if (args.tenant_id) {
    where.push(`tenant_id = $${i++}::uuid`);
    params.push(args.tenant_id);
  }
  if (args.property_id) {
    where.push(`property_id = $${i++}::uuid`);
    params.push(args.property_id);
  }
  if (args.status) {
    where.push(`status = $${i++}::invoice_status`);
    params.push(args.status);
  }

  params.push(args.limit);
  const limitIdx = i++;
  params.push(args.offset);
  const offsetIdx = i++;

  const { rows } = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${limitIdx} OFFSET $${offsetIdx};
    `,
    params
  );

  return rows;
}

export async function applyInvoicePayment(
  client: PoolClient,
  args: { invoice_id: string; amount: number }
): Promise<RentInvoiceRow> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    UPDATE public.rent_invoices ri
    SET
      paid_amount = COALESCE(ri.paid_amount, 0) + $2::numeric,
      paid_at = CASE
        WHEN (COALESCE(ri.paid_amount, 0) + $2::numeric) >= ri.total_amount THEN NOW()
        ELSE ri.paid_at
      END,
      status = CASE
        WHEN (COALESCE(ri.paid_amount, 0) + $2::numeric) >= ri.total_amount THEN 'paid'::invoice_status
        ELSE ri.status
      END
    WHERE ri.id = $1::uuid
      AND ri.deleted_at IS NULL
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [args.invoice_id, args.amount]
  );
  return rows[0]!;
}
TS

echo "✅ wrote src/repos/rent_invoices.repo.ts"


# ----------------------------
# 3) Service: add payRentInvoice (payments + invoice_payments + update invoice)
# ----------------------------
cat > src/services/rent_invoices.service.ts <<'TS'
import type { PoolClient } from "pg";
import type { InvoiceStatus, PaymentMethod } from "../schemas/rent_invoices.schema.js";
import {
  findRentInvoiceByTenancyPeriod,
  insertRentInvoice,
  listRentInvoices,
  getRentInvoiceByIdForUpdate,
  applyInvoicePayment,
} from "../repos/rent_invoices.repo.js";

type TenancyMini = {
  id: string;
  tenant_id: string;
  property_id: string;
  listing_id: string | null;
  rent_amount: string;
};

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
      listing_id,
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

export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: PaymentMethod;
    amount?: number; // if omitted, pay remaining
  }
): Promise<{
  invoice: any;
  payment_id: string;
  applied_amount: number;
}> {
  // Lock invoice
  const invoice = await getRentInvoiceByIdForUpdate(client, args.invoiceId);
  if (!invoice) {
    const e: any = new Error("Invoice not found");
    e.code = "INVOICE_NOT_FOUND";
    throw e;
  }

  if (invoice.status === "void" || invoice.status === "cancelled") {
    const e: any = new Error(`Invoice not payable (status=${invoice.status})`);
    e.code = "INVOICE_NOT_PAYABLE";
    throw e;
  }

  const total = Number(invoice.total_amount || "0");
  const paid = Number(invoice.paid_amount || "0");
  const remaining = Math.max(0, total - paid);

  if (remaining <= 0) {
    const e: any = new Error("Invoice already fully paid");
    e.code = "INVOICE_ALREADY_PAID";
    throw e;
  }

  const amount = typeof args.amount === "number" ? args.amount : remaining;
  if (amount <= 0) {
    const e: any = new Error("Amount must be > 0");
    e.code = "AMOUNT_INVALID";
    throw e;
  }
  if (amount > remaining) {
    const e: any = new Error(`Amount exceeds remaining balance (${remaining})`);
    e.code = "AMOUNT_TOO_HIGH";
    throw e;
  }

  // Need listing_id for payments table
  const { rows: tenRows } = await client.query<{ listing_id: string | null }>(
    `
    SELECT listing_id
    FROM public.tenancies
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    LIMIT 1;
    `,
    [invoice.tenancy_id]
  );

  const listingId = tenRows[0]?.listing_id ?? null;
  if (!listingId) {
    const e: any = new Error("Cannot pay invoice: tenancy has no listing_id");
    e.code = "LISTING_ID_MISSING";
    throw e;
  }

  // Create payment row (successful for now)
  const currency = (invoice.currency ?? "USD") || "USD";

  const { rows: payRows } = await client.query<{ id: string }>(
    `
    INSERT INTO public.payments (
      tenant_id,
      listing_id,
      property_id,
      amount,
      currency,
      status,
      transaction_reference,
      payment_method,
      initiated_at,
      completed_at
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::uuid,
      $4::numeric,
      $5::varchar(3),
      'successful'::payment_status,
      ('invpay_' || $6::text || '_' || replace(gen_random_uuid()::text,'-','')),
      $7::payment_method,
      NOW(),
      NOW()
    )
    RETURNING id;
    `,
    [
      invoice.tenant_id,
      listingId,
      invoice.property_id,
      amount,
      currency,
      invoice.invoice_number ?? "0",
      args.paymentMethod,
    ]
  );

  const paymentId = payRows[0]!.id;

  // Link invoice -> payment (admin/service policy expects this)
  await client.query(
    `
    INSERT INTO public.invoice_payments (
      invoice_id,
      payment_id,
      amount,
      organization_id
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::numeric,
      $4::uuid
    )
    ON CONFLICT (invoice_id, payment_id) DO NOTHING;
    `,
    [invoice.id, paymentId, amount, invoice.organization_id]
  );

  // Update invoice paid fields/status
  const updated = await applyInvoicePayment(client, {
    invoice_id: invoice.id,
    amount,
  });

  return { invoice: updated, payment_id: paymentId, applied_amount: amount };
}
TS

echo "✅ wrote src/services/rent_invoices.service.ts"


# ----------------------------
# 4) Routes: add POST /v1/rent-invoices/:id/pay
# ----------------------------
cat > src/routes/rent_invoices.ts <<'TS'
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import {
  generateRentInvoiceForTenancy,
  getRentInvoices,
  payRentInvoice,
} from "../services/rent_invoices.service.js";
import {
  GenerateRentInvoiceBodySchema,
  ListRentInvoicesQuerySchema,
  PayRentInvoiceBodySchema,
} from "../schemas/rent_invoices.schema.js";

function assertAuth(req: any) {
  const sub = req?.user?.sub;
  if (!sub) {
    const e: any = new Error("Missing authenticated user id (req.user.sub)");
    e.code = "USER_ID_MISSING";
    throw e;
  }
}

function assertAdmin(req: any) {
  const role = req?.user?.role;
  if (role !== "admin") {
    const e: any = new Error("Admin only for now (policy requires admin or service role).");
    e.code = "FORBIDDEN";
    throw e;
  }
}

/**
 * Rent invoices routes
 */
export async function rentInvoicesRoutes(app: FastifyInstance) {
  // Generate invoice for a tenancy (ADMIN/owner/agent allowed by DB policy; we keep auth check)
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    try {
      assertAuth(req);

      const params = z.object({ id: z.string().uuid() }).parse(req.params);
      const body = GenerateRentInvoiceBodySchema.parse(req.body);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply
          .code(500)
          .send({ ok: false, error: "PG_NOT_CONFIGURED", message: "Fastify pg plugin not found at app.pg" });
      }

      const client = await pgAny.connect();
      try {
        await client.query("BEGIN");

        const res = await generateRentInvoiceForTenancy(client, {
          tenancyId: params.id,
          periodStart: body.periodStart,
          periodEnd: body.periodEnd,
          dueDate: body.dueDate,
          subtotal: body.subtotal,
          lateFeeAmount: body.lateFeeAmount,
          currency: body.currency,
          status: body.status,
          notes: body.notes,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, reused: res.reused, data: res.row });
      } catch (err: any) {
        await client.query("ROLLBACK");
        return reply.code(500).send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({ ok: false, error: err?.code ?? "BAD_REQUEST", message: err?.message ?? String(err) });
    }
  });

  // List invoices
  app.get("/v1/rent-invoices", async (req, reply) => {
    try {
      assertAuth(req);

      const q = ListRentInvoicesQuerySchema.parse((req as any).query);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply
          .code(500)
          .send({ ok: false, error: "PG_NOT_CONFIGURED", message: "Fastify pg plugin not found at app.pg" });
      }

      const client = await pgAny.connect();
      try {
        const data = await getRentInvoices(client, {
          limit: q.limit,
          offset: q.offset,
          tenancyId: q.tenancyId,
          tenantId: q.tenantId,
          propertyId: q.propertyId,
          status: q.status,
        });
        return reply.send({ ok: true, data, paging: { limit: q.limit, offset: q.offset } });
      } catch (err: any) {
        return reply.code(500).send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({ ok: false, error: err?.code ?? "BAD_REQUEST", message: err?.message ?? String(err) });
    }
  });

  // PAY invoice (admin-only for now to match RLS policies)
  app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
    try {
      assertAuth(req);
      assertAdmin(req);

      const params = z.object({ id: z.string().uuid() }).parse(req.params);
      const body = PayRentInvoiceBodySchema.parse(req.body);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply
          .code(500)
          .send({ ok: false, error: "PG_NOT_CONFIGURED", message: "Fastify pg plugin not found at app.pg" });
      }

      const client = await pgAny.connect();
      try {
        await client.query("BEGIN");

        const res = await payRentInvoice(client, {
          invoiceId: params.id,
          paymentMethod: body.paymentMethod,
          amount: body.amount,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: res });
      } catch (err: any) {
        await client.query("ROLLBACK");
        return reply.code(500).send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({ ok: false, error: err?.code ?? "BAD_REQUEST", message: err?.message ?? String(err) });
    }
  });
}
TS

echo "✅ wrote src/routes/rent_invoices.ts"


# ----------------------------
# 5) Ensure routes/index.ts registers rentInvoicesRoutes ONCE
# ----------------------------
if [ -f src/routes/index.ts ]; then
  # Rewrite a clean known-good version to avoid duplicates
  cat > src/routes/index.ts <<'TS'
import type { FastifyInstance } from "fastify";

import { healthRoutes } from "./health.js";
import { demoRoutes } from "./demo.js";
import { meRoutes } from "./me.js";
import { organizationRoutes } from "./organizations.js";
import { authRoutes } from "./auth.js";
import { propertyRoutes } from "./properties.js";
import { viewingRoutes } from "./viewings.js";
import { listingRoutes } from "./listings.js";
import { applicationRoutes } from "./applications.js";
import { tenancyRoutes } from "./tenancies.js";
import { rentInvoicesRoutes } from "./rent_invoices.js";

export async function registerRoutes(app: FastifyInstance) {
  await app.register(healthRoutes);
  await app.register(demoRoutes);

  await app.register(authRoutes);
  await app.register(meRoutes);

  await app.register(organizationRoutes);
  await app.register(propertyRoutes);
  await app.register(tenancyRoutes);
  await app.register(viewingRoutes);
  await app.register(listingRoutes);
  await app.register(applicationRoutes);

  // Rent invoices
  await app.register(rentInvoicesRoutes);
}
TS
  echo "✅ wrote src/routes/index.ts (deduped)"
fi


# ----------------------------
# 6) Test helper script
# ----------------------------
cat > scripts/test_rent_invoice_pay.sh <<'BASH2'
#!/usr/bin/env bash
set -euo pipefail

: "${DB_NAME:=rentease}"
: "${API:=http://127.0.0.1:4000}"

eval "$(./scripts/login.sh)"
ORG_ID="$(curl -sS "$API/v1/me" -H "authorization: Bearer $TOKEN" | jq -r '.data.organization_id')"

echo "API=$API"
echo "ORG_ID=$ORG_ID"

INVOICE_ID="$(psql -d "$DB_NAME" -Atc "select id from public.rent_invoices where deleted_at is null order by created_at desc limit 1;")"
echo "INVOICE_ID=$INVOICE_ID"

echo "---- BEFORE"
psql -d "$DB_NAME" -c "select invoice_number,status,total_amount,paid_amount,paid_at from public.rent_invoices where id='$INVOICE_ID';" >/dev/null

echo "---- PAY (admin-only)"
curl -sS -X POST "$API/v1/rent-invoices/$INVOICE_ID/pay" \
  -H "content-type: application/json" \
  -H "authorization: Bearer $TOKEN" \
  -H "x-organization-id: $ORG_ID" \
  -d '{"paymentMethod":"card"}' | jq

echo "---- AFTER"
psql -d "$DB_NAME" -c "select invoice_number,status,total_amount,paid_amount,paid_at from public.rent_invoices where id='$INVOICE_ID';"
BASH2

chmod +x scripts/test_rent_invoice_pay.sh
chmod +x scripts/fix_rent_invoice_pay.sh

echo "✅ Created scripts/fix_rent_invoice_pay.sh"
echo "✅ Created scripts/test_rent_invoice_pay.sh"
echo "➡️ Run:"
echo "   ./scripts/fix_rent_invoice_pay.sh"
echo "   npm run dev"
echo "   ./scripts/test_rent_invoice_pay.sh"
