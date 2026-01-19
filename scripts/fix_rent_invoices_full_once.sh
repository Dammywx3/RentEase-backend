#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTE="$ROOT/src/routes/rent_invoices.ts"
REPO="$ROOT/src/repos/rent_invoices.repo.ts"
SERVICE="$ROOT/src/services/rent_invoices.service.ts"

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"

for f in "$ROUTE" "$REPO" "$SERVICE"; do
  if [ -f "$f" ]; then
    cp "$f" "$ROOT/scripts/.bak/$(basename "$f").bak.$ts"
    echo "✅ backup -> scripts/.bak/$(basename "$f").bak.$ts"
  fi
done

# -----------------------
# 1) ROUTE (applyDbContext + admin pay + alreadyPaid)
# -----------------------
cat > "$ROUTE" <<'TS'
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
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

type AuthReq = {
  user?: { sub?: string; role?: string };
  jwtVerify?: () => Promise<void>;
  params?: any;
  body?: any;
  query?: any;
  headers?: any;
};

async function ensureAuth(app: FastifyInstance, req: any, reply: any) {
  try {
    if (typeof req?.jwtVerify === "function") {
      await req.jwtVerify();
      return null;
    }
    if (typeof (app as any).authenticate === "function") {
      await (app as any).authenticate(req, reply);
      return null;
    }
    return reply.code(500).send({
      ok: false,
      error: "JWT_NOT_CONFIGURED",
      message: "jwtVerify/app.authenticate not found. Ensure JWT plugin is registered.",
    });
  } catch {
    return reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Unauthorized" });
  }
}

function requireUserId(req: any) {
  const sub = req?.user?.sub;
  if (!sub) {
    const e: any = new Error("Missing authenticated user id (req.user.sub)");
    e.code = "USER_ID_MISSING";
    throw e;
  }
  return sub as string;
}

/**
 * IMPORTANT:
 * Your DB function current_organization_uuid() reads:
 * - request.header.x_organization_id
 * - request.jwt.claim.org, request.jwt.claims.org, request.jwt.claim.organization_id
 * - app.organization_id
 *
 * So we set all of them (safe + future-proof).
 */
async function applyDbContext(client: PoolClient, req: any) {
  const h = (req?.headers ?? {}) as Record<string, any>;
  const orgId =
    h["x-organization-id"] ??
    h["x-organization-id".toLowerCase()] ??
    h["x_organization_id"] ??
    h["x_organization_id".toLowerCase()];

  const userId = req?.user?.sub ?? "";
  const role = req?.user?.role ?? "";

  if (!orgId) {
    const e: any = new Error("Missing x-organization-id header");
    e.code = "ORG_ID_MISSING";
    throw e;
  }

  const org = String(orgId);
  const uid = userId ? String(userId) : "";
  const r = role ? String(role) : "";

  // ORG context
  await client.query("SELECT set_config('request.header.x_organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claim.org', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claims.org', $1, true);", [org]);
  await client.query("SELECT set_config('request.jwt.claim.organization_id', $1, true);", [org]);
  await client.query("SELECT set_config('app.organization_id', $1, true);", [org]);

  // USER context (if you use current_user_uuid())
  await client.query("SELECT set_config('request.jwt.claim.sub', $1, true);", [uid]);
  await client.query("SELECT set_config('app.user_id', $1, true);", [uid]);
  await client.query("SELECT set_config('rentease.user_id', $1, true);", [uid]);

  // ROLE (optional)
  await client.query("SELECT set_config('rentease.user_role', $1, true);", [r]);
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // Generate invoice for a tenancy
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      requireUserId(req);

      const params = z.object({ id: z.string().uuid() }).parse((req as any).params);
      const body = GenerateRentInvoiceBodySchema.parse((req as any).body);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({
          ok: false,
          error: "PG_NOT_CONFIGURED",
          message: "Fastify pg plugin not found at app.pg",
        });
      }

      const client = (await pgAny.connect()) as PoolClient;
      try {
        await applyDbContext(client, req);
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
        try { await client.query("ROLLBACK"); } catch {}
        return reply.code(500).send({
          ok: false,
          error: err?.code ?? "INTERNAL_ERROR",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({
        ok: false,
        error: err?.code ?? "BAD_REQUEST",
        message: err?.message ?? String(err),
      });
    }
  });

  // List invoices
  app.get("/v1/rent-invoices", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      requireUserId(req);

      const q = ListRentInvoicesQuerySchema.parse((req as any).query);

      const pgAny: any = (app as any).pg;
      if (!pgAny?.connect) {
        return reply.code(500).send({
          ok: false,
          error: "PG_NOT_CONFIGURED",
          message: "Fastify pg plugin not found at app.pg",
        });
      }

      const client = (await pgAny.connect()) as PoolClient;
      try {
        await applyDbContext(client, req);

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
        return reply.code(500).send({
          ok: false,
          error: err?.code ?? "INTERNAL_ERROR",
          message: err?.message ?? String(err),
        });
      } finally {
        client.release();
      }
    } catch (err: any) {
      return reply.code(400).send({
        ok: false,
        error: err?.code ?? "BAD_REQUEST",
        message: err?.message ?? String(err),
      });
    }
  });

  // Pay invoice (admin-only for now)
  app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    const anyReq = req as unknown as AuthReq;
    const userId = anyReq.user?.sub;
    if (!userId) {
      return reply.code(401).send({
        ok: false,
        error: "USER_ID_MISSING",
        message: "Missing authenticated user id (req.user.sub)",
      });
    }

    const pgAny: any = (app as any).pg;
    if (!pgAny?.connect) {
      return reply.code(500).send({
        ok: false,
        error: "PG_NOT_CONFIGURED",
        message: "Fastify pg plugin not found at app.pg",
      });
    }

    const params = z.object({ id: z.string().uuid() }).parse((anyReq as any).params);
    const body = PayRentInvoiceBodySchema.parse((anyReq as any).body);

    const client = (await pgAny.connect()) as PoolClient;
    try {
      await applyDbContext(client, req);

      // Avoid TS "underline red": don't use generic typing here.
      const roleRes = await client.query(
        "select role from public.users where id = $1::uuid limit 1;",
        [userId]
      );
      const dbRole = (roleRes.rows?.[0]?.role ?? null) as string | null;

      if (dbRole !== "admin") {
        return reply.code(403).send({
          ok: false,
          error: "FORBIDDEN",
          message: "Admin only for now (policy requires admin or service role).",
        });
      }

      anyReq.user = anyReq.user ?? {};
      anyReq.user.role = "admin";

      await client.query("BEGIN");

      const res = await payRentInvoice(client, {
        invoiceId: params.id,
        paymentMethod: body.paymentMethod,
        amount: body.amount,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, alreadyPaid: res.alreadyPaid, data: res.row });
    } catch (err: any) {
      try { await client.query("ROLLBACK"); } catch {}
      return reply.code(500).send({
        ok: false,
        error: err?.code ?? "INTERNAL_ERROR",
        message: err?.message ?? String(err),
      });
    } finally {
      client.release();
    }
  });
}
TS

echo "✅ wrote: src/routes/rent_invoices.ts"

# -----------------------
# 2) REPO (insert ALWAYS sets organization_id from DB context)
# -----------------------
cat > "$REPO" <<'TS'
import type { PoolClient } from "pg";
import type { InvoiceStatus } from "../schemas/rent_invoices.schema.js";

type InsertArgs = {
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
  args: { tenancy_id: string; period_start: string; period_end: string; due_date: string }
) {
  const { rows } = await client.query(
    `
    SELECT ${RENT_INVOICE_SELECT}
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
  const vals: any[] = [];
  let i = 1;

  if (args.tenancy_id) { where.push(`tenancy_id = $${i++}::uuid`); vals.push(args.tenancy_id); }
  if (args.tenant_id) { where.push(`tenant_id = $${i++}::uuid`); vals.push(args.tenant_id); }
  if (args.property_id) { where.push(`property_id = $${i++}::uuid`); vals.push(args.property_id); }
  if (args.status) { where.push(`status = $${i++}::invoice_status`); vals.push(args.status); }

  vals.push(args.limit);
  vals.push(args.offset);

  const { rows } = await client.query(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE ${where.join(" AND ")}
    ORDER BY created_at DESC
    LIMIT $${i++} OFFSET $${i++};
    `,
    vals
  );

  return rows;
}

/**
 * CRITICAL FIX:
 * organization_id must NOT be NULL.
 * We set it explicitly from current_organization_uuid(),
 * which reads from set_config() values we apply in the route.
 */
export async function insertRentInvoice(client: PoolClient, args: InsertArgs) {
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
    )
    VALUES (
      public.current_organization_uuid(),
      $1::uuid,
      $2::uuid,
      $3::uuid,
      $4::date,
      $5::date,
      $6::date,
      $7::numeric,
      $8::numeric,
      $9::numeric,
      $10::varchar,
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

  return rows[0];
}
TS

echo "✅ wrote: src/repos/rent_invoices.repo.ts"

# -----------------------
# 3) SERVICE (generate uses repo insert; pay returns {row, alreadyPaid})
# -----------------------
cat > "$SERVICE" <<'TS'
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
    SELECT id, tenant_id, property_id, rent_amount::text AS rent_amount
    FROM public.tenancies
    WHERE id = $1::uuid AND deleted_at IS NULL
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
 * PAY:
 * - does NOT create payments rows (your DB enforces payment amount == listing price)
 * - marks invoice paid
 * - returns alreadyPaid boolean
 */
export async function payRentInvoice(
  client: PoolClient,
  args: {
    invoiceId: string;
    paymentMethod: string;
    amount?: number | null;
  }
): Promise<{ row: RentInvoiceRow; alreadyPaid: boolean }> {
  const invRes = await client.query<RentInvoiceRow>(
    `
    SELECT ${RENT_INVOICE_SELECT}
    FROM public.rent_invoices
    WHERE id = $1::uuid AND deleted_at IS NULL
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

  const updRes = await client.query<RentInvoiceRow>(
    `
    UPDATE public.rent_invoices
    SET
      status = 'paid'::invoice_status,
      paid_amount = $2::numeric,
      paid_at = NOW()
    WHERE id = $1::uuid AND deleted_at IS NULL
    RETURNING ${RENT_INVOICE_SELECT};
    `,
    [args.invoiceId, amount]
  );

  return { row: updRes.rows[0]!, alreadyPaid: false };
}
TS

echo "✅ wrote: src/services/rent_invoices.service.ts"

echo ""
echo "== DONE =="
echo "1) Restart server: npm run dev"
echo "2) Test generate:"
echo '   curl -sS -X POST "$API/v1/tenancies/$TENANCY_ID/rent-invoices/generate" -H "content-type: application/json" -H "authorization: Bearer $TOKEN" -H "x-organization-id: $ORG_ID" -d '"'"'{"periodStart":"2026-08-01","periodEnd":"2026-08-31","dueDate":"2026-09-01","subtotal":2000,"currency":"USD","notes":"Aug rent"}'"'"' | jq'
