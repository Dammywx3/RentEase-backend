// src/routes/rent_invoices.ts
import type { FastifyInstance } from "fastify";
import type { PoolClient } from "pg";
import { z } from "zod";

import { setPgContext } from "../db/set_pg_context.js";

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

// -------------------------------
// Helpers (✅ trust middleware only)
// -------------------------------
function requireOrgId(req: any, reply: any): string | null {
  const orgId = String(req.orgId ?? "").trim(); // ✅ set by app.authenticate
  if (!orgId) {
    reply.code(400).send({
      ok: false,
      error: "ORG_REQUIRED",
      message: "x-organization-id required",
    });
    return null;
  }
  return orgId;
}

function requireUserId(req: any, reply: any): string | null {
  const userId = String(req.user?.userId ?? "").trim(); // ✅ normalized by auth middleware
  if (!userId) {
    reply.code(401).send({
      ok: false,
      error: "UNAUTHORIZED",
      message: "Missing authenticated user",
    });
    return null;
  }
  return userId;
}

async function fetchDbRole(client: PoolClient, userId: string) {
  const roleRes = await client.query<{ role: string }>(
    "select role from public.users where id = $1::uuid limit 1;",
    [userId]
  );
  return roleRes.rows[0]?.role ?? null;
}

/**
 * ✅ DB context setter
 * Uses ONLY:
 * - req.orgId (resolved & org-matched)
 * - req.user.userId (normalized)
 * - req.user.role (normalized, but we can refresh from DB)
 */
async function applyDbContext(client: PoolClient, req: any) {
  const orgId = String(req.orgId ?? "").trim();
  const userId = String(req.user?.userId ?? "").trim();
  const role = String(req.user?.role ?? "").trim();

  if (!orgId) {
    const e: any = new Error("Missing resolved organization id (req.orgId)");
    e.code = "ORG_ID_MISSING";
    throw e;
  }
  if (!userId) {
    const e: any = new Error("Missing authenticated user id (req.user.userId)");
    e.code = "USER_ID_MISSING";
    throw e;
  }
  await setPgContext(client, { userId, organizationId: orgId, role, eventNote: "rent_invoices" });
}

export async function rentInvoicesRoutes(app: FastifyInstance) {
  // ------------------------------------------------------------
  // POST /v1/rent-invoices/tenancies/:id/generate
  // ------------------------------------------------------------
  app.post(
    "/tenancies/:id/generate",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      try {
        const orgId = requireOrgId(req, reply);
        const userId = requireUserId(req, reply);
        if (!orgId || !userId) return;

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
          // Optional: refresh role from DB
          const dbRole = await fetchDbRole(client, userId);
          (req as any).user.role = (dbRole ?? (req as any).user.role) as any;

          await applyDbContext(client, req);
          await client.query("BEGIN");

        await client.query("SET LOCAL TIME ZONE 'UTC'");
          const res = await generateRentInvoiceForTenancy(client, {
            organizationId: orgId,
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
          try {
            await client.query("ROLLBACK");
          } catch {}
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
    }
  );

  // ------------------------------------------------------------
  // GET /rent-invoices
  // ------------------------------------------------------------
  app.get("/", { preHandler: [app.authenticate] }, async (req, reply) => {
    try {
      const orgId = requireOrgId(req, reply);
      const userId = requireUserId(req, reply);
      if (!orgId || !userId) return;

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
        const dbRole = await fetchDbRole(client, userId);
        (req as any).user.role = (dbRole ?? (req as any).user.role) as any;

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

  // ------------------------------------------------------------
  // POST /rent-invoices/:id/pay (admin-only for now)
  // ------------------------------------------------------------
  app.post("/:id/pay", { preHandler: [app.authenticate] }, async (req, reply) => {
    const orgId = requireOrgId(req, reply);
    const userId = requireUserId(req, reply);
    if (!orgId || !userId) return;

    const pgAny: any = (app as any).pg;
    if (!pgAny?.connect) {
      return reply.code(500).send({
        ok: false,
        error: "PG_NOT_CONFIGURED",
        message: "Fastify pg plugin not found at app.pg",
      });
    }

    const params = z.object({ id: z.string().uuid() }).parse((req as any).params);
    const body = PayRentInvoiceBodySchema.parse((req as any).body);

    const client = (await pgAny.connect()) as PoolClient;
    try {
      const dbRole = await fetchDbRole(client, userId);
      (req as any).user.role = (dbRole ?? (req as any).user.role) as any;

      await applyDbContext(client, req);

      if (dbRole !== "admin") {
        return reply.code(403).send({ ok: false, error: "FORBIDDEN", message: "Admin only for now." });
      }

      await client.query("BEGIN");

      const res = await payRentInvoice(client, {
        invoiceId: params.id,
        paymentMethod: String(body.paymentMethod),
        amount: body.amount ?? null,
      });

      await client.query("COMMIT");
      return reply.send({ ok: true, alreadyPaid: res.alreadyPaid, data: res.row });
    } catch (err: any) {
      try {
        await client.query("ROLLBACK");
      } catch {}
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
