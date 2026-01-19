#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ts="$(date +%Y%m%d_%H%M%S)"

backup() {
  local f="$1"
  if [ -f "$f" ]; then
    cp "$f" "$f.bak.$ts"
  fi
}

mkdir -p src/schemas src/repos src/services src/routes scripts

backup "src/schemas/rent_invoices.schema.ts"
backup "src/repos/rent_invoices.repo.ts"
backup "src/services/rent_invoices.service.ts"
backup "src/routes/rent_invoices.ts"
backup "src/routes/index.ts"
backup "src/server.ts"
backup "scripts/patch_org_context.sql"

# ------------------------------------------------------------
# 0) DB PATCH: make current_organization_uuid() work reliably
#    Uses ONLY valid GUC keys (no hyphens).
# ------------------------------------------------------------
cat > scripts/patch_org_context.sql <<'SQL'
BEGIN;

-- Ensure current_organization_uuid() can read org from multiple valid sources.
-- This avoids invalid GUC name like: request.header.x-organization-id
CREATE OR REPLACE FUNCTION public.current_organization_uuid()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(
    COALESCE(
      current_setting('request.jwt.claim.org', true),
      current_setting('request.jwt.claims.org', true),
      current_setting('request.jwt.claim.organization_id', true),
      current_setting('request.header.x_organization_id', true),
      current_setting('app.organization_id', true)
    ),
    ''
  )::uuid;
$$;

COMMIT;
SQL

# Run DB patch (requires DB_NAME env or defaults to rentease)
DB_NAME="${DB_NAME:-rentease}"
echo "Using DB_NAME=$DB_NAME"
psql -d "$DB_NAME" -v ON_ERROR_STOP=1 -f scripts/patch_org_context.sql >/dev/null
echo "✅ Patched DB function current_organization_uuid()"

# ------------------------------------------------------------
# 1) ZOD SCHEMA: src/schemas/rent_invoices.schema.ts
# ------------------------------------------------------------
cat > src/schemas/rent_invoices.schema.ts <<'TS'
import { z } from "zod";

export const InvoiceStatus = z.enum([
  "draft",
  "issued",
  "paid",
  "overdue",
  "void",
  "cancelled",
]);

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

  currency: z.string().length(3).optional().nullable(),
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

export const GenerateRentInvoiceParamsSchema = z.object({
  id: z.string().uuid(),
});

export const GenerateRentInvoiceBodySchema = z.object({
  periodStart: z.string(), // YYYY-MM-DD
  periodEnd: z.string(),   // YYYY-MM-DD
  dueDate: z.string(),     // YYYY-MM-DD

  subtotal: z.number().positive().optional(),          // default from tenancy.rent_amount
  lateFeeAmount: z.number().min(0).optional().nullable(),
  currency: z.string().length(3).optional().nullable().default("USD"),
  status: InvoiceStatus.optional().nullable().default("issued"),
  notes: z.string().optional().nullable(),
});
TS

# ------------------------------------------------------------
# 2) REPO: src/repos/rent_invoices.repo.ts
# ------------------------------------------------------------
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
TS

# ------------------------------------------------------------
# 3) SERVICE: src/services/rent_invoices.service.ts
# ------------------------------------------------------------
cat > src/services/rent_invoices.service.ts <<'TS'
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
TS

# ------------------------------------------------------------
# 4) ROUTES: src/routes/rent_invoices.ts
#    Uses existing pg Pool from config/database.js
#    Sets RLS session context safely (NO invalid GUC keys)
# ------------------------------------------------------------
cat > src/routes/rent_invoices.ts <<'TS'
import type { FastifyInstance } from "fastify";
import {
  GenerateRentInvoiceBodySchema,
  GenerateRentInvoiceParamsSchema,
  ListRentInvoicesQuerySchema,
} from "../schemas/rent_invoices.schema.js";
import { generateRentInvoiceForTenancy, getRentInvoices } from "../services/rent_invoices.service.js";
import { pool } from "../config/database.js";

function getOrgIdFromHeaders(headers: any): string | null {
  const v = headers?.["x-organization-id"] ?? headers?.["X-Organization-Id"] ?? headers?.["x-Organization-id"];
  if (!v) return null;
  return Array.isArray(v) ? v[0] : String(v);
}

async function setRlsContext(client: any, userId: string, orgId: string) {
  // IMPORTANT: Postgres GUC keys must be valid identifiers (no hyphens).
  await client.query(
    `
    SELECT
      set_config('request.jwt.claim.sub', $1, true),
      set_config('request.jwt.claim.org', $2, true),
      set_config('request.header.x_organization_id', $2, true),
      set_config('app.organization_id', $2, true);
    `,
    [userId, orgId]
  );
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // Generate invoice for a tenancy
  app.post(
    "/v1/tenancies/:id/rent-invoices/generate",
    { preHandler: [(app as any).authenticate] },
    async (req: any, reply) => {
      const params = GenerateRentInvoiceParamsSchema.parse(req.params);
      const body = GenerateRentInvoiceBodySchema.parse(req.body);

      const userId = req.user?.sub;
      if (!userId) {
        return reply.code(401).send({ ok: false, error: "USER_ID_MISSING", message: "Missing authenticated user id (req.user.sub)" });
      }

      const orgId = getOrgIdFromHeaders(req.headers);
      if (!orgId) {
        return reply.code(400).send({ ok: false, error: "ORG_HEADER_MISSING", message: "Missing x-organization-id header" });
      }

      // Optional: block tenant from generating invoices (your RLS insert policy also blocks tenant)
      const role = req.user?.role;
      if (role === "tenant") {
        return reply.code(403).send({
          ok: false,
          error: "FORBIDDEN",
          message: "Tenants cannot generate rent invoices. Use landlord/agent/admin.",
        });
      }

      const client = await pool.connect();
      try {
        await client.query("BEGIN");
        await setRlsContext(client, userId, orgId);

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
    }
  );

  // List invoices
  app.get(
    "/v1/rent-invoices",
    { preHandler: [(app as any).authenticate] },
    async (req: any, reply) => {
      const q = ListRentInvoicesQuerySchema.parse(req.query);

      const userId = req.user?.sub;
      if (!userId) {
        return reply.code(401).send({ ok: false, error: "USER_ID_MISSING", message: "Missing authenticated user id (req.user.sub)" });
      }

      const orgId = getOrgIdFromHeaders(req.headers);
      if (!orgId) {
        return reply.code(400).send({ ok: false, error: "ORG_HEADER_MISSING", message: "Missing x-organization-id header" });
      }

      const client = await pool.connect();
      try {
        await setRlsContext(client, userId, orgId);

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
    }
  );
}
TS

# ------------------------------------------------------------
# 5) ROUTE REGISTER: src/routes/index.ts
#    Fix double/triple registration
# ------------------------------------------------------------
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

# ------------------------------------------------------------
# 6) SERVER: src/server.ts
#    Remove duplicate registerRoutes(app) calls
# ------------------------------------------------------------
cat > src/server.ts <<'TS'
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

  // 4) Routes (Fastify way)
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

# Remove CRLF (if any)
sed -i '' $'s/\r$//' \
  src/schemas/rent_invoices.schema.ts \
  src/repos/rent_invoices.repo.ts \
  src/services/rent_invoices.service.ts \
  src/routes/rent_invoices.ts \
  src/routes/index.ts \
  src/server.ts \
  scripts/patch_org_context.sql || true

echo "✅ Rent invoices full fix applied."
echo "➡️ Now restart: npm run dev"
