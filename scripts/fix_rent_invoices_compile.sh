#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo "== Rent invoices compile fix =="
echo "ROOT=$ROOT"

backup() { [ -f "$1" ] && cp "$1" "$1.bak.$(date +%Y%m%d_%H%M%S)"; }
ensure_dir() { mkdir -p "$1"; }

SCHEMA="src/schemas/rent_invoices.schema.ts"
REPO="src/repos/rent_invoices.repo.ts"
SERVICE="src/services/rent_invoices.service.ts"
ROUTE="src/routes/rent_invoices.ts"
ROUTES_INDEX="src/routes/index.ts"
SERVER="src/server.ts"

ensure_dir "src/schemas"
backup "$SCHEMA"
cat > "$SCHEMA" <<'TS'
import { z } from "zod";

export const InvoiceStatus = z.enum(["draft", "issued", "paid", "overdue", "void", "cancelled"]);
export type InvoiceStatus = z.infer<typeof InvoiceStatus>;

export const RentInvoiceRowSchema = z.object({
  id: z.string().uuid(),
  organization_id: z.string().uuid(),
  tenancy_id: z.string().uuid(),
  tenant_id: z.string().uuid(),
  property_id: z.string().uuid(),

  invoice_number: z.string().nullable().optional(),
  status: InvoiceStatus,

  period_start: z.string(),
  period_end: z.string(),
  due_date: z.string(),

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
  status: InvoiceStatus.optional(),
});

export const GenerateRentInvoiceBodySchema = z.object({
  periodStart: z.string(),
  periodEnd: z.string(),
  dueDate: z.string(),
  subtotal: z.number().optional(),
  lateFeeAmount: z.number().nullable().optional(),
  currency: z.string().length(3).nullable().optional(),
  status: InvoiceStatus.nullable().optional(),
  notes: z.string().nullable().optional(),
});
TS
echo "✅ wrote $SCHEMA"

ensure_dir "src/repos"
backup "$REPO"
cat > "$REPO" <<'TS'
import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";

export type RentInvoiceRow = {
  id: string;
  organization_id: string;
  tenancy_id: string;
  tenant_id: string;
  property_id: string;

  invoice_number: string | null;
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
  invoice_number::text as invoice_number,
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

export async function findRentInvoiceByTenancyPeriod(
  client: PoolClient,
  args: { tenancy_id: string; period_start: string; period_end: string; due_date: string }
): Promise<RentInvoiceRow | null> {
  const { rows } = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE deleted_at IS NULL
      AND tenancy_id = $1::uuid
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
      tenancy_id, tenant_id, property_id,
      period_start, period_end, due_date,
      subtotal, late_fee_amount, total_amount,
      currency, status, notes
    )
    VALUES (
      $1::uuid, $2::uuid, $3::uuid,
      $4::date, $5::date, $6::date,
      $7::numeric, $8::numeric, $9::numeric,
      $10::varchar(3), $11::invoice_status, $12::text
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

  if (args.tenancy_id) { where.push(`tenancy_id = $${i++}::uuid`); params.push(args.tenancy_id); }
  if (args.tenant_id) { where.push(`tenant_id = $${i++}::uuid`); params.push(args.tenant_id); }
  if (args.property_id) { where.push(`property_id = $${i++}::uuid`); params.push(args.property_id); }
  if (args.status) { where.push(`status = $${i++}::invoice_status`); params.push(args.status); }

  params.push(args.limit); const limitIdx = i++;
  params.push(args.offset); const offsetIdx = i++;

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
echo "✅ wrote $REPO"

ensure_dir "src/services"
backup "$SERVICE"
cat > "$SERVICE" <<'TS'
import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";
import { findRentInvoiceByTenancyPeriod, insertRentInvoice, listRentInvoices } from "../repos/rent_invoices.repo.js";

type TenancyMini = { id: string; tenant_id: string; property_id: string; rent_amount: string };

export async function getRentInvoices(
  client: PoolClient,
  args: { limit: number; offset: number; tenancyId?: string; tenantId?: string; propertyId?: string; status?: InvoiceStatus }
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
    SELECT id, tenant_id, property_id, rent_amount::text AS rent_amount
    FROM public.tenancies
    WHERE id = $1::uuid AND deleted_at IS NULL
    LIMIT 1;
    `,
    [args.tenancyId]
  );

  const tenancy = rows[0];
  if (!tenancy) { const e: any = new Error("Tenancy not found"); e.code = "TENANCY_NOT_FOUND"; throw e; }

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
TS
echo "✅ wrote $SERVICE"

ensure_dir "src/routes"
backup "$ROUTE"
cat > "$ROUTE" <<'TS'
import type { FastifyInstance } from "fastify";
import { ListRentInvoicesQuerySchema, GenerateRentInvoiceBodySchema } from "../schemas/rent_invoices.schema.js";
import { generateRentInvoiceForTenancy, getRentInvoices } from "../services/rent_invoices.service.js";

export async function rentInvoicesRoutes(app: FastifyInstance) {
  app.get("/v1/rent-invoices", async (req, reply) => {
    try {
      const q = ListRentInvoicesQuerySchema.parse((req as any).query);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({ ok: false, error: "PG_NOT_CONFIGURED", message: "Fastify pg plugin not found at app.pg" });
      }

      const client = await pgAny.connect();
      try {
        const data = await getRentInvoices(client, q);
        return reply.send({ ok: true, data, paging: { limit: q.limit, offset: q.offset } });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({ ok: false, error: err?.code ?? "BAD_REQUEST", message: err?.message ?? String(err) });
    }
  });

  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    try {
      const tenancyId = (req.params as any).id as string;

      const user: any = (req as any).user;
      if (!user?.sub) {
        return reply.code(401).send({ ok: false, error: "USER_ID_MISSING", message: "Missing authenticated user id (req.user.sub)" });
      }

      const orgId = (req.headers["x-organization-id"] as string | undefined) ?? "";
      if (!orgId) {
        return reply.code(400).send({ ok: false, error: "ORG_CONTEXT_MISSING", message: "Missing x-organization-id header" });
      }

      const body = GenerateRentInvoiceBodySchema.parse(req.body);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({ ok: false, error: "PG_NOT_CONFIGURED", message: "Fastify pg plugin not found at app.pg" });
      }

      const client = await pgAny.connect();
      try {
        await client.query("BEGIN");

        // RLS context (matches your earlier fixes)
        await client.query(`SELECT set_config('request.header.x-organization-id', $1, true)`, [orgId]);
        await client.query(`SELECT set_config('request.jwt.claim.sub', $1, true)`, [String(user.sub)]);

        const res = await generateRentInvoiceForTenancy(client, {
          tenancyId,
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
}
TS
echo "✅ wrote $ROUTE"

ensure_dir "src/routes"
backup "$ROUTES_INDEX"
cat > "$ROUTES_INDEX" <<'TS'
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

  await app.register(rentInvoicesRoutes);
}
TS
echo "✅ wrote $ROUTES_INDEX"

backup "$SERVER"
if [ -f "$SERVER" ]; then
  # remove accidental duplicate registerRoutes call if present
  perl -0777 -i -pe 's/\n\s*await\s+await\s+registerRoutes\(app\);\s*\n/\n/g' "$SERVER" || true
fi

echo "✅ server.ts cleaned (if it had duplicate registerRoutes)."
echo "✅ Done. Now run: npm run dev"
