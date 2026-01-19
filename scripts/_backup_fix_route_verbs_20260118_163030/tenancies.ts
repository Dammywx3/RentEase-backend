// src/routes/tenancies.ts
import type { FastifyInstance, FastifyReply } from "fastify";

import {
  createTenancyBodySchema,
  listTenanciesQuerySchema,
  endTenancyParamsSchema,
  endTenancyBodySchema,
  startTenancyParamsSchema,
  startTenancyBodySchema,
  type CreateTenancyBody,
  type ListTenanciesQuery,
  type EndTenancyBody,
  type EndTenancyParams,
  type StartTenancyBody,
  type StartTenancyParams,
} from "../schemas/tenancies.schema.js";

import { setPgContext } from "../db/set_pg_context.js";
import { createTenancy, endTenancy, getTenancies, startTenancy } from "../services/tenancies.service.js";

function getOrgId(req: any): string {
  return String(req?.orgId ?? "").trim();
}

function getActorId(req: any): string {
  // ✅ prefer user.id (matches your login response)
  return String(
    req?.user?.id ||
      req?.userId ||
      req?.user?.userId ||
      req?.sub ||
      req?.user?.sub ||
      ""
  ).trim();
}

function getRole(req: any): string | null {
  return (req as any)?.user?.role || (req as any)?.role || null;
}

function requireCtx(req: any, reply: FastifyReply): { userId: string; organizationId: string; role: string | null } | null {
  const userId = getActorId(req);
  if (!userId) {
    reply.code(401).send({ ok: false, error: "UNAUTHORIZED", message: "Missing authenticated user" });
    return null;
  }

  const organizationId = getOrgId(req);
  if (!organizationId) {
    reply.code(400).send({ ok: false, error: "ORG_REQUIRED", message: "Organization not resolved (x-organization-id/orgId)" });
    return null;
  }

  return { userId, organizationId, role: getRole(req) };
}

export async function tenancyRoutes(app: FastifyInstance) {
  // ------------------------------------------------------------
  // GET /tenancies
  // ------------------------------------------------------------
  app.get<{ Querystring: ListTenanciesQuery }>(
    "/tenancies",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const ctx = requireCtx(req, reply);
      if (!ctx) return;

      const q = listTenanciesQuerySchema.parse(req.query ?? {});

      const client = await app.pg.connect();
      try {
        await client.query("BEGIN");
        await client.query("SET LOCAL TIME ZONE 'UTC'");
        await setPgContext(client, { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role });

        const data = await getTenancies(client, {
          limit: q.limit,
          offset: q.offset,
          tenantId: q.tenantId,
          propertyId: q.propertyId,
          listingId: q.listingId,
          status: q.status as any,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data, paging: { limit: q.limit, offset: q.offset } });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        req.log.error(e);
        return reply.code(400).send({ ok: false, error: "TENANCIES_LIST_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // POST /tenancies
  // ------------------------------------------------------------
  app.post<{ Body: CreateTenancyBody }>(
    "/tenancies",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const ctx = requireCtx(req, reply);
      if (!ctx) return;

      const body = createTenancyBodySchema.parse(req.body ?? {});

      const client = await app.pg.connect();
      try {
        await client.query("BEGIN");
        await setPgContext(client, { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role });

        const result = await createTenancy(client, {
          tenantId: body.tenantId,
          propertyId: body.propertyId,
          listingId: body.listingId ?? null,
          rentAmount: body.rentAmount,
          securityDeposit: body.securityDeposit ?? null,
          startDate: body.startDate,
          nextDueDate: body.nextDueDate,
          paymentCycle: (body.paymentCycle as any) ?? null,
          status: (body.status as any) ?? null,
          terminationReason: body.terminationReason ?? null,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: result.row, reused: result.reused, patched: result.patched });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        req.log.error(e);
        return reply.code(400).send({ ok: false, error: "TENANCY_CREATE_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // PATCH /tenancies/:id/end
  // ------------------------------------------------------------
  app.patch<{ Params: EndTenancyParams; Body: EndTenancyBody }>(
    "/tenancies/:id/end",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const ctx = requireCtx(req, reply);
      if (!ctx) return;

      const params = endTenancyParamsSchema.parse(req.params ?? {});
      const body = endTenancyBodySchema.parse(req.body ?? {});

      const client = await app.pg.connect();
      try {
        await client.query("BEGIN");
        await setPgContext(client, { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role });

        const result = await endTenancy(client, {
          id: params.id,
          status: body.status,
          endDate: body.endDate ?? null,
          terminationReason: body.terminationReason ?? null,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: result.row, changed: result.changed });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        req.log.error(e);
        return reply.code(400).send({ ok: false, error: "TENANCY_END_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );

  // ------------------------------------------------------------
  // PATCH /tenancies/:id/start
  // ------------------------------------------------------------
  app.patch<{ Params: StartTenancyParams; Body: StartTenancyBody }>(
    "/tenancies/:id/start",
    { preHandler: [app.authenticate] },
    async (req, reply) => {
      const ctx = requireCtx(req, reply);
      if (!ctx) return;

      const params = startTenancyParamsSchema.parse(req.params ?? {});
      const body = startTenancyBodySchema.parse(req.body ?? {});

      const client = await app.pg.connect();
      try {
        await client.query("BEGIN");
        await setPgContext(client, { userId: ctx.userId, organizationId: ctx.organizationId, role: ctx.role });

        const result = await startTenancy(client, {
          id: params.id,
          startDate: body.startDate ?? null,
        });

        await client.query("COMMIT");
        return reply.send({ ok: true, data: result.row, changed: result.changed });
      } catch (e: any) {
        try { await client.query("ROLLBACK"); } catch {}
        req.log.error(e);
        return reply.code(400).send({ ok: false, error: "TENANCY_START_FAILED", message: e?.message || String(e) });
      } finally {
        client.release();
      }
    }
  );
}