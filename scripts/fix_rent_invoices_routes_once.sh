#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROUTE="$ROOT/src/routes/rent_invoices.ts"

mkdir -p "$ROOT/scripts/.bak"
ts="$(date +%Y%m%d_%H%M%S)"
if [ -f "$ROUTE" ]; then
  cp "$ROUTE" "$ROOT/scripts/.bak/rent_invoices.ts.bak.$ts"
  echo "✅ backup -> scripts/.bak/rent_invoices.ts.bak.$ts"
fi

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

function requireOrgId(req: any) {
  const orgId = req?.headers?.["x-organization-id"] ?? req?.headers?.["X-Organization-Id"];
  if (!orgId) {
    const e: any = new Error("Missing x-organization-id header");
    e.code = "ORG_ID_MISSING";
    throw e;
  }
  return String(orgId);
}

/**
 * IMPORTANT:
 * Your DB uses DEFAULT current_organization_uuid().
 * That default reads from session config; if not set, org_id becomes NULL => insert fails.
 * So we set org + user context for this connection before doing any queries.
 */
async function applyPgContext(client: PoolClient, orgId: string, userId: string) {
  await client.query(
    `
    select
      set_config('request.organization_id', $1, true),
      set_config('request.org_id',          $1, true),
      set_config('app.organization_id',     $1, true),
      set_config('rentease.organization_id',$1, true),
      set_config('request.user_id',         $2, true),
      set_config('request.sub',             $2, true),
      set_config('request.jwt.claim.sub',   $2, true)
    ;
    `,
    [orgId, userId]
  );
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // -----------------------------
  // Generate invoice for a tenancy
  // -----------------------------
  app.post("/v1/tenancies/:id/rent-invoices/generate", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      const userId = requireUserId(req);
      const orgId = requireOrgId(req);

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
        await applyPgContext(client, orgId, userId);

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

  // -----------------------------
  // List invoices
  // -----------------------------
  app.get("/v1/rent-invoices", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      const userId = requireUserId(req);
      const orgId = requireOrgId(req);

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
        await applyPgContext(client, orgId, userId);

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

  // -----------------------------
  // Pay invoice (admin-only, checked from DB)
  // -----------------------------
  app.post("/v1/rent-invoices/:id/pay", async (req, reply) => {
    const authResp = await ensureAuth(app, req, reply);
    if (authResp) return authResp;

    try {
      const anyReq = req as unknown as AuthReq;

      const userId = requireUserId(anyReq);
      const orgId = requireOrgId(anyReq);

      const params = z.object({ id: z.string().uuid() }).parse((anyReq as any).params);
      const body = PayRentInvoiceBodySchema.parse((anyReq as any).body);

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
        await applyPgContext(client, orgId, userId);

        // DB role check
        const roleRes = await client.query<{ role: string }>(
          "select role from public.users where id = $1::uuid limit 1;",
          [userId]
        );
        const dbRole = roleRes.rows[0]?.role;

        if (dbRole !== "admin") {
          return reply.code(403).send({
            ok: false,
            error: "FORBIDDEN",
            message: "Admin only for now (policy requires admin or service role).",
          });
        }

        // satisfy downstream checks if anything uses req.user.role
        anyReq.user = anyReq.user ?? {};
        anyReq.user.role = "admin";

        await client.query("BEGIN");
        const before = await client.query<{ status: string }>(
          "select status from public.rent_invoices where id = $1::uuid and deleted_at is null limit 1;",
          [params.id]
        );
        const wasPaid = before.rows[0]?.status === "paid";

        const row = await payRentInvoice(client, {
          invoiceId: params.id,
          paymentMethod: body.paymentMethod,
          amount: body.amount,
        });
        await client.query("COMMIT");

        return reply.send({ ok: true, alreadyPaid: wasPaid, data: row });
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
}
TS

echo "✅ Fixed: src/routes/rent_invoices.ts"
echo "➡️ Restart server: npm run dev"
