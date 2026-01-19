#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)"

echo "📍 Project: $ROOT_DIR"

# ---------- helpers ----------
write_file () {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
  echo "✅ Wrote $path"
}

# ---------- 1) Schema: src/schemas/rent_invoices.schema.ts ----------
write_file "src/schemas/rent_invoices.schema.ts" <<'TS'
import { z } from "zod";

export const InvoiceStatus = z.enum(["draft", "issued", "paid", "overdue", "void", "cancelled"]);
export type InvoiceStatus = z.infer<typeof InvoiceStatus>;

export const RentInvoiceRowSchema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid(),
  tenancy_id: z.string().uuid(),
  tenant_id: z.string().uuid(),
  property_id: z.string().uuid(),

  invoice_number: z.coerce.number().int().nullable().optional(),
  status: InvoiceStatus,

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
  deleted_at: z.string().nullable().optional(),
});

export const ListRentInvoicesQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(200).default(20),
  offset: z.coerce.number().int().min(0).default(0),
  tenancyId: z.string().uuid().optional(),
  tenantId: z.string().uuid().optional(),
  propertyId: z.string().uuid().optional(),
  status: InvoiceStatus.optional(),
});

export const GenerateRentInvoiceBodySchema = z.object({
  periodStart: z.string(), // YYYY-MM-DD
  periodEnd: z.string(),   // YYYY-MM-DD
  dueDate: z.string(),     // YYYY-MM-DD

  subtotal: z.number().positive().optional(),
  lateFeeAmount: z.number().min(0).nullable().optional(),
  currency: z.string().length(3).nullable().optional(),
  status: InvoiceStatus.nullable().optional(),
  notes: z.string().nullable().optional(),
});

export const PayRentInvoiceBodySchema = z.object({
  // Payment method must match enum payment_method in DB: card | bank_transfer | wallet
  paymentMethod: z.enum(["card", "bank_transfer", "wallet"]).default("card"),

  // optional: if omitted, we pay the remaining balance
  amount: z.number().positive().optional(),

  // optional override (usually invoice currency is used)
  currency: z.string().length(3).optional(),
});
TS

# ---------- 2) Repo: src/repos/rent_invoices.repo.ts ----------
write_file "src/repos/rent_invoices.repo.ts" <<'TS'
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

export async function findRentInvoiceById(
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

export async function findRentInvoiceByIdForUpdate(
  client: PoolClient,
  invoiceId: string
): Promise<RentInvoiceRow | null> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    FOR UPDATE
    LIMIT 1;
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

export async function markRentInvoicePaid(
  client: PoolClient,
  args: {
    invoice_id: string;
    paid_amount: number;
    paid_at_iso: string; // ISO string
    status: InvoiceStatus; // usually "paid"
  }
): Promise<RentInvoiceRow> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    UPDATE public.rent_invoices
    SET
      paid_amount = $2::numeric,
      paid_at = $3::timestamptz,
      status = $4::invoice_status,
      updated_at = NOW()
    WHERE id = $1::uuid
      AND deleted_at IS NULL
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [args.invoice_id, args.paid_amount, args.paid_at_iso, args.status]
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
TS

# ---------- 3) Service: src/services/rent_invoices.service.ts ----------
write_file "src/services/rent_invoices.service.ts" <<'TS'
import type { PoolClient } from "pg";
import crypto from "crypto";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";
import {
  findRentInvoiceByTenancyPeriod,
  insertRentInvoice,
  listRentInvoices,
  findRentInvoiceByIdForUpdate,
  markRentInvoicePaid,
} from "../repos/rent_invoices.repo.js";

type TenancyMini = {
  id: string;
  tenant_id: string;
  property_id: string;
  listing_id: string | null;
  rent_amount: string;
};

type PaymentRowMini = { id: string };

function num(x: any): number {
  const n = Number(x);
  return Number.isFinite(n) ? n : 0;
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
  // Idempotency: reuse if same period already exists
  const existing = await findRentInvoiceByTenancyPeriod(client, {
    tenancy_id: args.tenancyId,
    period_start: args.periodStart,
    period_end: args.periodEnd,
    due_date: args.dueDate,
  });
  if (existing) return { row: existing, reused: true };

  // Load tenancy basics
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

/**
 * PAY RENT INVOICE
 * Creates:
 * - payments row (successful)
 * - invoice_payments row (link)
 * - updates rent_invoices: paid_amount, paid_at, status='paid'
 *
 * Notes:
 * - payments requires listing_id (NOT NULL) => tenancy.listing_id must exist.
 * - invoice_payments insert policy allows admin OR db role 'rentease_service'.
 */
export async function payRentInvoiceById(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: "card" | "bank_transfer" | "wallet";
    amount?: number;
    currency?: string;
  }
): Promise<{ invoice: any; payment_id: string }> {
  const inv = await findRentInvoiceByIdForUpdate(client, args.invoiceId);
  if (!inv) {
    const e: any = new Error("Invoice not found");
    e.code = "INVOICE_NOT_FOUND";
    throw e;
  }

  if (inv.status === "void" || inv.status === "cancelled") {
    const e: any = new Error(`Invoice is ${inv.status} and cannot be paid`);
    e.code = "INVOICE_NOT_PAYABLE";
    throw e;
  }

  const total = num(inv.total_amount);
  const alreadyPaid = num(inv.paid_amount ?? "0");
  const remaining = Math.max(0, total - alreadyPaid);

  if (remaining <= 0 || inv.status === "paid") {
    // idempotent-ish: if fully paid, just return
    return { invoice: inv, payment_id: "" };
  }

  const payAmount = typeof args.amount === "number" ? args.amount : remaining;
  if (payAmount <= 0 || payAmount > remaining + 0.00001) {
    const e: any = new Error(`Invalid amount. Remaining balance is ${remaining}`);
    e.code = "INVALID_PAYMENT_AMOUNT";
    throw e;
  }

  // Load tenancy to get listing_id required by payments table
  const { rows: tenRows } = await client.query<TenancyMini>(
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
    [inv.tenancy_id]
  );

  const tenancy = tenRows[0];
  if (!tenancy) {
    const e: any = new Error("Tenancy not found for invoice");
    e.code = "TENANCY_NOT_FOUND";
    throw e;
  }
  if (!tenancy.listing_id) {
    const e: any = new Error("Cannot create payment: tenancy.listing_id is NULL but payments.listing_id is NOT NULL");
    e.code = "LISTING_ID_REQUIRED";
    throw e;
  }

  const currency = (args.currency ?? inv.currency ?? "USD").toUpperCase();

  // Create payment
  const txRef = `inv_${inv.invoice_number ?? "na"}_${crypto.randomUUID()}`.slice(0, 100);

  const { rows: payRows } = await client.query<PaymentRowMini>(
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
      completed_at
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::uuid,
      $4::numeric,
      $5::varchar(3),
      'successful'::payment_status,
      $6::varchar(100),
      $7::payment_method,
      NOW()
    )
    RETURNING id;
    `,
    [
      inv.tenant_id,
      tenancy.listing_id,
      inv.property_id,
      payAmount,
      currency,
      txRef,
      args.paymentMethod,
    ]
  );

  const paymentId = payRows[0]?.id;
  if (!paymentId) {
    const e: any = new Error("Failed to create payment");
    e.code = "PAYMENT_CREATE_FAILED";
    throw e;
  }

  // Link invoice_payments
  await client.query(
    `
    INSERT INTO public.invoice_payments (
      invoice_id,
      payment_id,
      amount
    )
    VALUES (
      $1::uuid,
      $2::uuid,
      $3::numeric
    )
    ON CONFLICT (invoice_id, payment_id) DO NOTHING;
    `,
    [inv.id, paymentId, payAmount]
  );

  // Update invoice paid fields (pay full remaining => status paid)
  const newPaid = alreadyPaid + payAmount;
  const paidAtIso = new Date().toISOString();

  const updated = await markRentInvoicePaid(client, {
    invoice_id: inv.id,
    paid_amount: newPaid,
    paid_at_iso: paidAtIso,
    status: newPaid + 0.00001 >= total ? "paid" : inv.status,
  });

  return { invoice: updated, payment_id: paymentId };
}
TS

# ---------- 4) Routes: src/routes/rent_invoices.ts ----------
# Important: No app.pg usage. Uses pool from config/database if available.
# If your config/database exports a different symbol, change it here.
write_file "src/routes/rent_invoices.ts" <<'TS'
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { pool } from "../config/database.js";
import {
  generateRentInvoiceForTenancy,
  getRentInvoices,
  payRentInvoiceById,
} from "../services/rent_invoices.service.js";
import {
  GenerateRentInvoiceBodySchema,
  ListRentInvoicesQuerySchema,
  PayRentInvoiceBodySchema,
} from "../schemas/rent_invoices.schema.js";

/**
 * Sets RLS context variables used by your DB helper functions:
 * - request.jwt.claim.sub
 * - request.jwt.claim.role
 * - request.header.x_organization_id   (underscore, NOT hyphen)
 */
async function setRlsContext(client: any, req: any) {
  const orgId = (req.headers["x-organization-id"] ?? req.headers["x_organization_id"]) as string | undefined;
  const user = req.user as any;

  const userId = user?.sub || user?.id;
  const role = user?.role;

  if (!userId) {
    const e: any = new Error("Missing authenticated user id (req.user.sub)");
    e.code = "USER_ID_MISSING";
    throw e;
  }
  if (!orgId) {
    const e: any = new Error(
      "Missing organization context. Ensure x-organization-id is set and RLS context is applied."
    );
    e.code = "ORG_CONTEXT_MISSING";
    throw e;
  }

  await client.query(
    `
    SELECT
      set_config('request.jwt.claim.sub', $1, true),
      set_config('request.jwt.claim.role', $2, true),
      set_config('request.header.x_organization_id', $3, true);
    `,
    [userId, role ?? "", orgId]
  );
}

async function ensureAuth(req: any) {
  // fastify-jwt typically provides req.jwtVerify()
  if (typeof req.jwtVerify === "function") {
    await req.jwtVerify();
  }
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // List invoices
  app.get("/v1/rent-invoices", async (req, reply) => {
    try {
      await ensureAuth(req);

      const q = ListRentInvoicesQuerySchema.parse((req as any).query);

      const client = await pool.connect();
      try {
        await setRlsContext(client, req);

        const data = await getRentInvoices(client, {
          limit: q.limit,
          offset: q.offset,
          tenancyId: q.tenancyId,
          tenantId: q.tenantId,
          propertyId: q.propertyId,
          status: q.status,
        });

        return reply.send({ ok: true, data, paging: { limit: q.limit, offset: q.offset } });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply
        .code(500)
        .send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
    }
  });

  // Generate (idempotent) invoice for a tenancy
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    try {
      await ensureAuth(req);

      const params = z.object({ id: z.string().uuid() }).parse(req.params);
      const body = GenerateRentInvoiceBodySchema.parse(req.body);

      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        await setRlsContext(client, req);

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
        throw err;
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply
        .code(500)
        .send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
    }
  });

  /**
   * PAY invoice
   * POST /v1/rent-invoices/:id/pay
   * Body: { paymentMethod, amount?, currency? }
   *
   * Note: invoice_payments insert policy requires admin or DB user 'rentease_service'.
   * If you want tenants to pay, you must run this endpoint using the service DB role OR loosen policy.
   */
  app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
    try {
      await ensureAuth(req);

      const params = z.object({ id: z.string().uuid() }).parse(req.params);
      const body = PayRentInvoiceBodySchema.parse(req.body);

      const role = (req as any).user?.role;
      if (role !== "admin") {
        return reply.code(403).send({ ok: false, error: "FORBIDDEN", message: "Admin only for now (policy requires admin or service role)." });
      }

      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        await setRlsContext(client, req);

        const res = await payRentInvoiceById(client, {
          invoiceId: params.id,
          paymentMethod: body.paymentMethod,
          amount: body.amount,
          currency: body.currency,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: res.invoice, payment_id: res.payment_id });
      } catch (err: any) {
        await client.query("ROLLBACK");
        throw err;
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply
        .code(500)
        .send({ ok: false, error: err?.code ?? "INTERNAL_ERROR", message: err?.message ?? String(err) });
    }
  });
}
TS

# ---------- 5) Fix routes registration: src/routes/index.ts ----------
# Ensure rentInvoicesRoutes is registered ONCE, using app.register (correct Fastify pattern)
write_file "src/routes/index.ts" <<'TS'
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

  // ✅ register once
  await app.register(rentInvoicesRoutes);
}
TS

# ---------- 6) Fix server.ts (remove duplicate registerRoutes call) ----------
write_file "src/server.ts" <<'TS'
import "dotenv/config";
import Fastify from "fastify";

import { env } from "./config/env.js";
import { prisma } from "./lib/prisma.js";

import { registerCors } from "./plugins/cors.js";
import registerJwt from "./plugins/jwt.js";
import { registerSecurity } from "./plugins/security.js";

import { registerErrorHandler } from "./api/middleware/error.middleware.js";
import { registerRateLimit } from "./api/middleware/rateLimit.middleware.js";

import { registerRoutes } from "./routes/index.js";
import { closePool } from "./config/database.js";

async function start() {
  const app = Fastify({ logger: true });

  // 1) Error handler early
  registerErrorHandler(app);

  // 2) Core plugins
  await app.register(registerCors);
  await app.register(registerSecurity);
  await app.register(registerJwt);

  // 3) Global rate limit
  await app.register(registerRateLimit, {
    global: { max: 200, timeWindow: "1 minute" },
  });

  // 4) Routes ✅ correct Fastify way (registered once)
  await app.register(registerRoutes);

  // DB ping (temporary)
  app.get("/v1/db/ping", async () => {
    await prisma.$queryRaw`SELECT 1`;
    return { ok: true, db: "connected" };
  });

  // Graceful shutdown
  app.addHook("onClose", async () => {
    await prisma.$disconnect();
    await closePool();
  });

  await app.listen({ port: env.port, host: "0.0.0.0" });
}

start().catch((err) => {
  console.error(err);
  process.exit(1);
});
TS

# ---------- 7) Make sure script permissions ----------
chmod +x scripts/*.sh 2>/dev/null || true

echo ""
echo "🎉 Rent invoices PAY + cleanup applied."
echo "➡️ Next: restart server"
echo "   npm run dev"
echo ""
echo "➡️ Test (admin only):"
echo "   export API='http://127.0.0.1:4000'"
echo "   eval \"\$(./scripts/login.sh)\""
echo "   ORG_ID=\"\$(curl -sS \"\$API/v1/me\" -H \"authorization: Bearer \$TOKEN\" | jq -r '.data.organization_id')\""
echo "   INVOICE_ID=\"\$(psql -d \"\$DB_NAME\" -Atc \"select id from public.rent_invoices where deleted_at is null order by created_at desc limit 1;\")\""
echo "   curl -sS -X POST \"\$API/v1/rent-invoices/\$INVOICE_ID/pay\" \\"
echo "     -H \"content-type: application/json\" \\"
echo "     -H \"authorization: Bearer \$TOKEN\" \\"
echo "     -H \"x-organization-id: \$ORG_ID\" \\"
echo "     -d '{\"paymentMethod\":\"card\"}' | jq"
echo ""
TS
chmod +x /tmp/fix_rent_invoices_pay.sh 2>/dev/null || true

# The script above is intended to be saved by the user; do not auto-run here.
echo "✅ Script content generated. Save it as: scripts/fix_rent_invoices_pay.sh and run it."
